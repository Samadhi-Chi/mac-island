import Foundation
import os.log

actor CodexAppServerMonitor {
    static let shared = CodexAppServerMonitor()

    private struct ParsedSubagentMetadata {
        let parentThreadId: String?
        let depth: Int?
        let nickname: String?
        let role: String?
    }

    struct ThreadDiagnosticsSnapshot: Codable, Sendable {
        let threadId: String
        let name: String?
        let preview: String?
        let cwd: String?
        let path: String?
        let statusType: String?
        let isEphemeral: Bool
        let updatedAt: Date?
        let placeholderCandidate: Bool
    }

    private enum PendingRequestKind {
        case commandApproval
        case fileApproval
        case permissionsApproval
        case userInput
    }

    private struct PendingRequest {
        let requestId: String
        let threadId: String
        let kind: PendingRequestKind
        let intervention: SessionIntervention
        let requestedPermissions: [String: Any]?
    }

    private struct PendingResponse {
        let method: String
        let continuation: CheckedContinuation<[String: Any], Error>
    }

    private let logger = Logger(
        subsystem: MacIslandProductPolicy.loggingSubsystem,
        category: "Codex"
    )
    private let port: Int
    static let maximumWebSocketMessageSize = 32 * 1024 * 1024

    nonisolated static func shouldIncludeLocalTurns(requested: Bool) -> Bool {
        MacIslandProductPolicy.localConversationTurnsEnabled && requested
    }

    private var process: Process?
    private var processStopTask: Task<Void, Never>?
    private var ownedProcessNeedsCleanup = false
    private var shutdownRequested = false
    private var websocket: (any CodexMonitorTransport)?
    private var receiveTask: Task<Void, Never>?
    private var threadListRefreshTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var requestTimeouts: [String: Task<Void, Never>] = [:]
    private var recovery = CodexMonitorRecovery()
    private var requestSequence = 0
    private var pendingResponses: [String: PendingResponse] = [:]
    private var pendingRequestsByThread: [String: PendingRequest] = [:]
    private var threadApprovalModes: [String: String] = [:]  // threadId → approvalMode
    private var recoveredNotLoadedThreadVersions: [String: String] = [:]
    private var resolvedClientBundleIdentifier: String?
    private var resolvedClientName: String?
    private var lastThreadDiagnostics: [ThreadDiagnosticsSnapshot] = []

    private nonisolated static let notLoadedRecoveryWindow: TimeInterval = 10 * 60
    private nonisolated static let maximumFutureActivitySkew: TimeInterval = 60

    private let transportFactory: (@Sendable (URL) -> any CodexMonitorTransport)?
    private let suspensionProvider: @Sendable () async -> Bool
    private let retrySleep: @Sendable (TimeInterval) async throws -> Void
    private let requestTimeout: Duration
    private let allowsOwnedServerLaunch: Bool
    private let executableResolver: @Sendable () async -> String?
    private let ownedProcessStop: @Sendable (Process) async -> CodexOwnedProcessShutdown.Result
    private let sessionLookup: @Sendable (String) async -> SessionState?
    private let rolloutReader: @Sendable (String, String, SessionClientInfo) async -> CodexThreadSnapshot?

    init(
        port: Int = 41241,
        transportFactory: (@Sendable (URL) -> any CodexMonitorTransport)? = nil,
        suspensionProvider: @escaping @Sendable () async -> Bool = {
            await MainActor.run { !EnergyGovernor.shared.policy.allowsFileWatcherRetry }
        },
        retrySleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
            try await Task.sleep(for: .seconds($0))
        },
        requestTimeout: Duration = .seconds(10),
        allowsOwnedServerLaunch: Bool = true,
        executableResolver: @escaping @Sendable () async -> String? = {
            await CodexAppServerMonitor.resolveCodexExecutable()
        },
        ownedProcessStop: @escaping @Sendable (Process) async -> CodexOwnedProcessShutdown.Result = {
            await CodexOwnedProcessShutdown.stop($0)
        },
        sessionLookup: @escaping @Sendable (String) async -> SessionState? = CodexAppServerMonitor.lookupSession,
        rolloutReader: @escaping @Sendable (String, String, SessionClientInfo) async -> CodexThreadSnapshot? =
            CodexAppServerMonitor.readRollout
    ) {
        self.port = port
        self.transportFactory = transportFactory
        self.suspensionProvider = suspensionProvider
        self.retrySleep = retrySleep
        self.requestTimeout = requestTimeout
        self.allowsOwnedServerLaunch = allowsOwnedServerLaunch
        self.executableResolver = executableResolver
        self.ownedProcessStop = ownedProcessStop
        self.sessionLookup = sessionLookup
        self.rolloutReader = rolloutReader
    }

    nonisolated private static func lookupSession(_ id: String) async -> SessionState? {
        await SessionStore.shared.session(for: id)
    }

    nonisolated private static func readRollout(_ id: String, _ cwd: String, _ info: SessionClientInfo) async
        -> CodexThreadSnapshot?
    {
        await CodexRolloutParser.shared.parseThread(threadId: id, fallbackCwd: cwd, clientInfo: info)
    }

    func start() async {
        releaseExitedOwnedProcess()
        guard !shutdownRequested, processStopTask == nil, !ownedProcessNeedsCleanup, !Task.isCancelled else { return }
        recovery.enable()
        let generation = recovery.generation
        let suspended = await suspensionProvider()
        guard !shutdownRequested, processStopTask == nil, !ownedProcessNeedsCleanup,
            recovery.generation == generation, recovery.enabled, !Task.isCancelled
        else { return }
        if recovery.setSuspended(suspended) { cancelConnectionWork() }
        guard !recovery.suspended else { return }
        if let connectionTask {
            await connectionTask.value
            return
        }
        guard retryTask == nil, let token = recovery.begin() else { return }
        let task = Task<Void, Never> { [weak self] in
            await self?.establishConnection(token: token)
        }
        connectionTask = task
        await task.value
        if recovery.generation == token { connectionTask = nil }
    }

    func healthSnapshot() -> CodexMonitorHealth { recovery.health }

    /// Reconnect our own subscription; never terminate or restart an external client.
    func reconnect() async {
        releaseExitedOwnedProcess()
        guard !shutdownRequested, processStopTask == nil, !ownedProcessNeedsCleanup,
            recovery.health.phase != .connecting
        else { return }
        recovery.enable()
        recovery.invalidate()
        cancelConnectionWork()
        await start()
    }

    func setSuspended(_ suspended: Bool) async {
        releaseExitedOwnedProcess()
        guard !shutdownRequested, processStopTask == nil, !ownedProcessNeedsCleanup else { return }
        guard recovery.setSuspended(suspended) else { return }
        cancelConnectionWork()
        if !suspended, recovery.enabled { await start() }
    }

    private func establishConnection(token: UInt64) async {
        // Only injected offline transports may connect without an owned child.
        if transportFactory != nil, await connectToServer(token: token) { return }
        guard recovery.accepts(token), !Task.isCancelled else { return }
        guard allowsOwnedServerLaunch else {
            connectionFailed(token: token, reason: .initializationFailed)
            return
        }

        if transportFactory == nil, process != nil {
            await retireOwnedProcess()
            guard !ownedProcessNeedsCleanup, recovery.accepts(token), !shutdownRequested, !Task.isCancelled else {
                return
            }
        }
        if process?.isRunning != true {
            let executable = await executableResolver()
            guard recovery.accepts(token), !Task.isCancelled else { return }
            guard let executable else {
                connectionFailed(token: token, reason: .executableMissing)
                return
            }
            resolvedClientBundleIdentifier = Self.bundleIdentifier(forCodexExecutable: executable)
            resolvedClientName = Self.clientName(forCodexExecutable: executable)
            let child = Process()
            child.executableURL = URL(fileURLWithPath: executable)
            child.arguments = ["app-server", "--listen", "stdio://", "-c", "analytics.enabled=false"]
            let input = Pipe()
            let output = Pipe()
            child.standardInput = input
            child.standardOutput = output
            child.standardError = FileHandle.nullDevice
            do {
                try child.run()
                process = child
                if transportFactory == nil {
                    websocket = CodexStdioTransport(
                        input: input.fileHandleForWriting, output: output.fileHandleForReading
                    )
                }
            } catch {
                connectionFailed(token: token, reason: .initializationFailed)
                return
            }
        }

        if transportFactory == nil {
            if !(await connectToServer(token: token)) {
                connectionFailed(token: token, reason: .initializationFailed)
            }
            return
        }
        for _ in 0..<12 {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard recovery.accepts(token) else { return }
            if await connectToServer(token: token) { return }
        }
        connectionFailed(token: token, reason: .initializationFailed)
    }

    private func connectionFailed(token: UInt64, reason: CodexMonitorHealth.Failure) {
        guard let delay = recovery.failed(token, reason: reason) else { return }
        // Initial discovery may still be awaiting a rollout read. Retire that
        // attempt now, so a retry cannot consume its timer just waiting for it.
        connectionTask?.cancel()
        connectionTask = nil
        disconnectTransport()
        guard retryTask == nil else { return }
        let sleep = retrySleep
        retryTask = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            await self?.retryConnection(token: token)
        }
    }

    private func retryConnection(token: UInt64) async {
        guard recovery.generation == token, recovery.enabled, !recovery.suspended else { return }
        retryTask = nil
        await start()
    }

    private func disconnectTransport() {
        threadListRefreshTask?.cancel()
        threadListRefreshTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        websocket?.cancel(with: .goingAway, reason: nil)
        websocket = nil
        recoveredNotLoadedThreadVersions.removeAll()
        threadApprovalModes.removeAll()
        // Server request IDs and interventions belong to the closed transport.
        // Fresh thread status can re-establish attention after reconnection.
        pendingRequestsByThread.removeAll()
        for task in requestTimeouts.values { task.cancel() }
        requestTimeouts.removeAll()
        let responses = pendingResponses
        pendingResponses.removeAll()
        for response in responses.values { response.continuation.resume(throwing: CancellationError()) }
    }

    private func cancelConnectionWork() {
        retryTask?.cancel()
        retryTask = nil
        connectionTask?.cancel()
        connectionTask = nil
        disconnectTransport()
    }

    private func releaseExitedOwnedProcess() {
        // A child may exit just after a bounded stop timed out. Retain it while
        // alive, but allow a later explicit start/reconnect once exit is known.
        guard processStopTask == nil, ownedProcessNeedsCleanup, process?.isRunning != true else { return }
        process = nil
        ownedProcessNeedsCleanup = false
    }

    /// Application termination is final, including for already queued startup
    /// and reconnect requests that reach this actor after cleanup finishes.
    func shutdown() async {
        shutdownRequested = true
        await stop()
    }

    func stop() async {
        recovery.stop()
        cancelConnectionWork()
        pendingRequestsByThread.removeAll()
        threadApprovalModes.removeAll()
        recoveredNotLoadedThreadVersions.removeAll()
        lastThreadDiagnostics.removeAll()
        await retireOwnedProcess()
    }

    private func retireOwnedProcess() async {
        if let processStopTask {
            await processStopTask.value
            return
        }
        guard let child = process else { return }
        ownedProcessNeedsCleanup = true
        // Keep the owned handle until exit is confirmed. A repeated stop joins
        // this task, and cancellation of the caller cannot abandon the child.
        let task = Task {
            let result = await ownedProcessStop(child)
            if result != .timedOut {
                process = nil
                ownedProcessNeedsCleanup = false
            } else {
                logger.error("Codex observer did not exit within the shutdown deadline")
            }
            // Complete state cleanup inside the shared task, so every caller
            // awaiting stop can safely request an ordinary restart afterwards.
            processStopTask = nil
        }
        processStopTask = task
        await task.value
    }

    func approve(threadId: String, forSession: Bool) async {
        guard !MacIslandProductPolicy.monitorOnly else { return }
        guard let pending = pendingRequestsByThread[threadId] else { return }
        let result: [String: Any]

        switch pending.kind {
        case .commandApproval:
            result = ["decision": forSession ? "acceptForSession" : "accept"]
        case .fileApproval:
            result = ["decision": forSession ? "acceptForSession" : "accept"]
        case .permissionsApproval:
            result = [
                "permissions": pending.requestedPermissions ?? [:],
                "scope": forSession ? "session" : "turn",
            ]
        case .userInput:
            return
        }

        await sendResponse(id: pending.requestId, result: result)
        pendingRequestsByThread.removeValue(forKey: threadId)
        await SessionStore.shared.resolveCodexIntervention(sessionId: threadId, nextPhase: .processing)
    }

    func deny(threadId: String) async {
        guard !MacIslandProductPolicy.monitorOnly else { return }
        guard let pending = pendingRequestsByThread[threadId] else { return }
        let result: [String: Any]

        switch pending.kind {
        case .commandApproval:
            result = ["decision": "decline"]
        case .fileApproval:
            result = ["decision": "decline"]
        case .permissionsApproval:
            result = [
                "permissions": [:],
                "scope": "turn",
            ]
        case .userInput:
            return
        }

        await sendResponse(id: pending.requestId, result: result)
        pendingRequestsByThread.removeValue(forKey: threadId)
        await SessionStore.shared.resolveCodexIntervention(sessionId: threadId, nextPhase: .processing)
    }

    func answer(threadId: String, answers: [String: [String]]) async -> Bool {
        guard !MacIslandProductPolicy.monitorOnly else { return false }
        guard let pending = pendingRequestsByThread[threadId], pending.kind == .userInput else { return false }

        await sendResponse(
            id: pending.requestId,
            result: Self.requestUserInputResponsePayload(answers: answers)
        )
        pendingRequestsByThread.removeValue(forKey: threadId)
        await SessionStore.shared.resolveCodexIntervention(sessionId: threadId, nextPhase: .processing)
        return true
    }

    func submitRequestUserInputOutput(
        threadId: String,
        callId: String,
        answers: [String: [String]]
    ) async throws {
        guard !MacIslandProductPolicy.monitorOnly else {
            throw MacIslandMonitorOnlyError.controlDisabled
        }
        if websocket == nil {
            await start()
        }

        let outputPayload = Self.requestUserInputResponsePayload(answers: answers)
        let outputData = try JSONSerialization.data(withJSONObject: outputPayload, options: [.sortedKeys])
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw NSError(
                domain: "CodexAppServer", code: 6,
                userInfo: [
                    NSLocalizedDescriptionKey: "Unable to encode Codex request_user_input answers."
                ])
        }

        _ = try await sendRequest(
            method: "thread/inject_items",
            params: [
                "threadId": threadId,
                "items": [
                    [
                        "type": "function_call_output",
                        "call_id": callId,
                        "output": output,
                    ]
                ],
            ]
        )

        await SessionStore.shared.resolveCodexIntervention(sessionId: threadId, nextPhase: .processing)
    }

    nonisolated static func requestUserInputResponsePayload(answers: [String: [String]]) -> [String: Any] {
        let formattedAnswers = answers.reduce(into: [String: Any]()) { partial, entry in
            partial[entry.key] = ["answers": entry.value]
        }
        return ["answers": formattedAnswers]
    }

    /// Read-only account quota lookup. This uses the app-server's canonical
    /// multi-bucket response instead of guessing the account quota from whichever
    /// model-specific `token_count` event happened to be written most recently.
    func readUsageSnapshot() async -> CodexUsageSnapshot? {
        if websocket == nil {
            await start()
        }
        guard websocket != nil else { return nil }

        do {
            let response = try await sendRequest(
                method: "account/rateLimits/read",
                params: NSNull()
            )
            return CodexUsageLoader.snapshotFromAppServerResponse(response)
        } catch {
            logger.debug(
                "Codex account/rateLimits/read failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Read only the native name through the existing connection. Unlike a
    /// snapshot read, this cannot start a server or import history into the
    /// SessionStore and make an old record appear as a current session.
    func readThreadName(threadId: String) async throws -> String? {
        let token = recovery.generation
        let response = try await sendRequest(
            method: "thread/read", params: ["threadId": threadId, "includeTurns": false]
        )
        guard recovery.accepts(token), !Task.isCancelled else { throw CancellationError() }
        guard let thread = response["thread"] as? [String: Any],
            thread["id"] as? String == threadId
        else {
            throw NSError(
                domain: "CodexAppServer", code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Invalid thread metadata response"
                ])
        }
        return SessionListTitle.fromNativeName(thread["name"] as? String).nativeName
    }

    func readThread(threadId: String, includeTurns: Bool = true) async throws -> CodexThreadSnapshot {
        if websocket == nil {
            await start()
        }

        let token = recovery.generation
        let response = try await sendRequest(
            method: "thread/read",
            params: [
                "threadId": threadId,
                // The user opted into rich local progress details. Turns are read
                // only into the in-memory SessionState and remain excluded from
                // persisted snapshots, caches, diagnostics, Bridge logs, and telemetry.
                "includeTurns": Self.shouldIncludeLocalTurns(requested: includeTurns),
            ]
        )

        guard recovery.accepts(token) else { throw CancellationError() }
        guard let thread = response["thread"] as? [String: Any],
            let snapshot = parseThreadSnapshot(thread)
        else {
            throw NSError(
                domain: "CodexAppServer", code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Invalid thread/read response"
                ])
        }

        await SessionStore.shared.syncCodexThreadSnapshot(snapshot)
        return snapshot
    }

    func startThread(cwd: String, model: String? = nil) async throws -> CodexThreadSnapshot {
        guard !MacIslandProductPolicy.monitorOnly else {
            throw MacIslandMonitorOnlyError.controlDisabled
        }
        if websocket == nil {
            await start()
        }

        let response = try await sendRequest(
            method: "thread/start",
            params: [
                "model": model as Any,
                "modelProvider": NSNull(),
                "profile": NSNull(),
                "cwd": cwd,
                "approvalPolicy": NSNull(),
                "sandbox": NSNull(),
                "config": NSNull(),
                "baseInstructions": NSNull(),
                "developerInstructions": NSNull(),
                "compactPrompt": NSNull(),
                "includeApplyPatchTool": NSNull(),
                "experimentalRawEvents": false,
                "persistExtendedHistory": true,
            ]
        )

        guard let thread = response["thread"] as? [String: Any],
            let threadId = thread["id"] as? String
        else {
            throw NSError(
                domain: "CodexAppServer", code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey: "Invalid thread/start response"
                ])
        }

        return try await readThread(threadId: threadId, includeTurns: true)
    }

    func resumeThread(threadId: String, cwd: String? = nil, model: String? = nil) async throws -> CodexThreadSnapshot {
        guard !MacIslandProductPolicy.monitorOnly else {
            throw MacIslandMonitorOnlyError.controlDisabled
        }
        if websocket == nil {
            await start()
        }

        let response = try await sendRequest(
            method: "thread/resume",
            params: [
                "threadId": threadId,
                "model": model as Any,
                "modelProvider": NSNull(),
                "cwd": cwd as Any,
                "approvalPolicy": NSNull(),
                "sandbox": NSNull(),
                "config": NSNull(),
                "baseInstructions": NSNull(),
                "developerInstructions": NSNull(),
                "persistExtendedHistory": true,
            ]
        )

        guard let thread = response["thread"] as? [String: Any],
            let resumedThreadID = thread["id"] as? String
        else {
            throw NSError(
                domain: "CodexAppServer", code: 5,
                userInfo: [
                    NSLocalizedDescriptionKey: "Invalid thread/resume response"
                ])
        }

        return try await readThread(threadId: resumedThreadID, includeTurns: true)
    }

    func archiveThread(threadId: String) async throws {
        guard !MacIslandProductPolicy.monitorOnly else {
            throw MacIslandMonitorOnlyError.controlDisabled
        }
        if websocket == nil {
            await start()
        }

        _ = try await sendRequest(
            method: "thread/archive",
            params: [
                "threadId": threadId
            ]
        )
    }

    func continueThread(threadId: String, expectedTurnId: String, text: String) async throws {
        guard !MacIslandProductPolicy.monitorOnly else {
            throw MacIslandMonitorOnlyError.controlDisabled
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if websocket == nil {
            await start()
        }

        _ = try await sendRequest(
            method: "turn/steer",
            params: [
                "threadId": threadId,
                "expectedTurnId": expectedTurnId,
                "input": [
                    [
                        "type": "text",
                        "text": trimmed,
                    ]
                ],
            ]
        )

        await SessionStore.shared.upsertCodexSession(
            sessionId: threadId,
            name: nil,
            preview: trimmed,
            cwd: nil,
            phase: .processing,
            intervention: nil
        )
    }

    func diagnosticsSnapshot() -> [ThreadDiagnosticsSnapshot] {
        guard MacIslandProductPolicy.monitorOnly else { return lastThreadDiagnostics }
        return lastThreadDiagnostics.map(Self.redactedDiagnosticsSnapshot(_:))
    }

    nonisolated static func redactedDiagnosticsSnapshot(
        _ snapshot: ThreadDiagnosticsSnapshot
    ) -> ThreadDiagnosticsSnapshot {
        ThreadDiagnosticsSnapshot(
            threadId: snapshot.threadId,
            name: nil,
            preview: nil,
            cwd: nil,
            path: nil,
            statusType: snapshot.statusType,
            isEphemeral: snapshot.isEphemeral,
            updatedAt: snapshot.updatedAt,
            placeholderCandidate: snapshot.placeholderCandidate
        )
    }

    func refreshThreadDiscovery(threadId: String) async {
        guard !threadId.isEmpty else { return }

        if websocket == nil {
            await start()
        }

        do {
            _ = try await readThread(threadId: threadId, includeTurns: false)
        } catch {
            logger.debug(
                "Codex thread/read refresh failed for \(threadId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            await refreshThreadList(reason: "usage-fallback")
        }
    }

    private func connectToServer(token: UInt64) async -> Bool {
        guard recovery.accepts(token), !Task.isCancelled else { return false }
        guard let url = URL(string: "ws://127.0.0.1:\(port)") else { return false }
        let socket: any CodexMonitorTransport
        if let transportFactory {
            socket = transportFactory(url)
        } else if let ownedTransport = websocket {
            socket = ownedTransport
        } else {
            return false
        }
        socket.resume()
        websocket = socket
        receiveTask = Task { [weak self] in await self?.receiveLoop(socket: socket, token: token) }
        do {
            _ = try await sendRequest(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "Island", "title": "Island",
                        "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
                    ],
                    "capabilities": ["experimentalApi": true],
                ])
            guard recovery.accepts(token), websocket === socket else { return false }
            let initialized = try Self.webSocketTextMessage(from: ["method": "initialized"])
            try await socket.send(.string(initialized))
            recovery.connected(token)
            await refreshThreadList(reason: "connect", token: token)
            guard recovery.accepts(token), websocket === socket else { return false }
            ensureThreadListRefreshLoop(token: token)
            return true
        } catch {
            if recovery.accepts(token), websocket === socket { disconnectTransport() }
            return false
        }
    }

    static func makeWebSocketTask(url: URL, session: URLSession = .shared) -> URLSessionWebSocketTask {
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = maximumWebSocketMessageSize
        return task
    }

    private func receiveLoop(socket: any CodexMonitorTransport, token: UInt64) async {
        while !Task.isCancelled, recovery.accepts(token), websocket === socket {
            do {
                let message = try await socket.receive()
                guard recovery.accepts(token), websocket === socket, !Task.isCancelled else { return }
                await handle(message, token: token)
            } catch {
                guard recovery.accepts(token), websocket === socket, !Task.isCancelled else { return }
                if recovery.health.phase == .connecting {
                    // Let the one connection attempt decide whether to launch its owned server.
                    disconnectTransport()
                } else {
                    connectionFailed(token: token, reason: .connectionLost)
                }
                return
            }
        }
    }

    private func ensureThreadListRefreshLoop(token: UInt64) {
        guard threadListRefreshTask == nil else { return }
        threadListRefreshTask = Task { [weak self] in await self?.runThreadListRefreshLoop(token: token) }
    }

    private func runThreadListRefreshLoop(token: UInt64) async {
        while !Task.isCancelled, recovery.accepts(token) {
            guard let interval = await currentThreadListRefreshInterval() else { return }
            do { try await Task.sleep(for: interval) } catch { return }
            guard !Task.isCancelled, recovery.accepts(token), websocket != nil else { return }
            guard await currentThreadListRefreshInterval() != nil else { continue }
            await refreshThreadList(reason: "poll", token: token)
        }
    }

    private func currentThreadListRefreshInterval() async -> Duration? {
        await MainActor.run { EnergyGovernor.shared.policy.codexThreadListRefreshInterval }
    }

    private func refreshThreadList(reason: String, token: UInt64? = nil) async {
        let token = token ?? recovery.generation
        guard websocket != nil, recovery.accepts(token) else { return }
        do {
            let response = try await sendRequest(method: "thread/list", params: Self.threadListRequestParams())
            guard recovery.accepts(token) else { return }
            await ingestThreadList(response, token: token)
        } catch {
            // Protocol-level errors do not prove the connection is broken.
            logger.debug("Codex thread/list refresh failed reason=\(reason, privacy: .public)")
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message, token: UInt64) async {
        guard recovery.accepts(token) else { return }
        let data: Data
        switch message {
        case .data(let raw):
            data = raw
        case .string(let text):
            data = Data(text.utf8)
        @unknown default:
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let method = json["method"] as? String {
            recovery.recordEvent(token, at: Date())
            if let idValue = json["id"], !(idValue is NSNull) {
                await handleServerRequest(
                    id: stringify(idValue),
                    method: method,
                    params: json["params"] as? [String: Any] ?? [:]
                )
            } else {
                await handleNotification(method: method, params: json["params"] as? [String: Any] ?? [:], token: token)
            }
            return
        }

        guard let idValue = json["id"] else { return }
        let id = stringify(idValue)

        if let response = pendingResponses.removeValue(forKey: id) {
            requestTimeouts.removeValue(forKey: id)?.cancel()
            let continuation = response.continuation
            if let result = json["result"] as? [String: Any] {
                if response.method != "initialize" { recovery.recordRead(token, at: Date()) }
                continuation.resume(returning: result)
            } else if json["result"] is NSNull {
                if response.method != "initialize" { recovery.recordRead(token, at: Date()) }
                continuation.resume(returning: [:])
            } else if let errorObject = json["error"] as? [String: Any] {
                let message = (errorObject["message"] as? String) ?? "Unknown Codex app-server error"
                continuation.resume(
                    throwing: NSError(
                        domain: "CodexAppServer", code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: message
                        ]))
            } else {
                continuation.resume(returning: [:])
            }
        }
    }

    private func handleNotification(method: String, params: [String: Any], token: UInt64) async {
        guard recovery.accepts(token) else { return }
        logger.info("Codex notification method=\(method, privacy: .public)")
        switch method {
        case "thread/status/changed":
            let threadId = (params["threadId"] as? String) ?? ""
            guard !threadId.isEmpty else { return }
            let statusType = ((params["status"] as? [String: Any])?["type"] as? String) ?? "unknown"
            logger.info(
                "Codex status changed thread=\(threadId, privacy: .public) statusType=\(statusType, privacy: .public)"
            )
            let phase = phaseFromCodexStatus(
                params["status"] as? [String: Any],
                threadId: threadId,
                intervention: pendingRequestsByThread[threadId]?.intervention
            )
            let hasExistingSession = await SessionStore.shared.containsSession(threadId)
            guard recovery.accepts(token) else { return }
            if !hasExistingSession, pendingRequestsByThread[threadId] == nil {
                logger.notice(
                    "Ignoring status-only update for unknown Codex thread=\(threadId, privacy: .public) statusType=\(statusType, privacy: .public)"
                )
                return
            }
            await SessionStore.shared.upsertCodexSession(
                sessionId: threadId,
                name: nil,
                preview: nil,
                cwd: nil,
                phase: phase,
                intervention: pendingRequestsByThread[threadId]?.intervention
            )

        case "item/autoApprovalReview/started":
            guard let threadId = params["threadId"] as? String,
                let session = await sessionLookup(threadId),
                session.clientInfo.kind == .codexCLI,
                let intervention = Self.guardianReviewIntervention(from: params)
            else {
                return
            }

            guard recovery.accepts(token) else { return }

            await SessionStore.shared.upsertCodexSession(
                sessionId: threadId,
                name: nil,
                preview: intervention.message,
                cwd: nil,
                phase: .waitingForInput,
                intervention: intervention
            )

        case "item/autoApprovalReview/completed":
            guard let threadId = params["threadId"] as? String else { return }
            await SessionStore.shared.resolveCodexIntervention(sessionId: threadId, nextPhase: .processing)
            guard recovery.accepts(token) else { return }
            // Keep receiving RPC responses while this follow-up read is pending.
            Task { [weak self] in
                await self?.refreshAfterNotification(threadId: threadId, token: token)
            }

        case "thread/started":
            if let thread = params["thread"] as? [String: Any] {
                let startedThreadId = (thread["id"] as? String) ?? "unknown"
                let namePresent = (thread["name"] as? String)?.isEmpty == false
                let previewPresent = (thread["preview"] as? String)?.isEmpty == false
                let pathPresent = (thread["path"] as? String)?.isEmpty == false
                logger.info(
                    "Codex thread started thread=\(startedThreadId, privacy: .public) namePresent=\(namePresent, privacy: .public) previewPresent=\(previewPresent, privacy: .public) pathPresent=\(pathPresent, privacy: .public)"
                )
                await ingestThread(thread)
            }

        case "thread/name/updated":
            guard let threadId = params["threadId"] as? String else { return }
            await SessionStore.shared.updateCodexThreadName(
                sessionId: threadId,
                name: params["threadName"] as? String
            )

        case "thread/archived":
            guard let threadId = params["threadId"] as? String else { return }
            logger.info("Codex thread archived thread=\(threadId, privacy: .public)")
            recoveredNotLoadedThreadVersions.removeValue(forKey: threadId)
            removeThreadDiagnostics(threadId: threadId)
            await SessionStore.shared.process(.sessionEnded(sessionId: threadId))

        case "account/rateLimits/updated":
            guard let rateLimits = params["rateLimits"] as? [String: Any],
                let snapshot = CodexUsageLoader.snapshotFromAppServerRateLimits(rateLimits),
                CodexUsageLoader.isMainCodexLimit(snapshot)
            else {
                return
            }
            let productSnapshot =
                MacIslandProductPolicy.privacyShieldEnabled
                ? snapshot.quotaOnlyProjection
                : snapshot
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .macIslandCodexUsageDidUpdate,
                    object: productSnapshot
                )
            }

        default:
            break
        }
    }

    private func refreshAfterNotification(threadId: String, token: UInt64) async {
        guard recovery.accepts(token) else { return }
        _ = try? await readThread(threadId: threadId, includeTurns: true)
    }

    // MARK: - Codex approval-policy helpers

    /// Returns `true` if the thread's approval policy is "never", meaning
    /// Codex auto-approves WebSocket approval requests without waiting for our response.
    ///
    /// Used for the WebSocket path (`item/*/requestApproval`).  The hook-based path
    /// uses `codexBypassPermissions` on the `HookEvent` instead, which is populated
    /// directly from `permission_mode=bypassPermissions` in the hook payload.
    ///
    /// Lookup order:
    /// 1. In-memory cache populated from WebSocket thread list / thread/read responses.
    /// 2. `~/.codex/.codex-global-state.json` — per-thread heartbeat entry only.
    private func isAutoApproveThread(_ threadId: String) -> Bool {
        if let cached = threadApprovalModes[threadId] {
            return cached == "never"
        }
        return Self.approvalPolicyFromGlobalState(threadId: threadId) == "never"
    }

    nonisolated static func approvalPolicyFromGlobalState(threadId: String) -> String? {
        guard
            let data = try? Data(
                contentsOf: URL(
                    fileURLWithPath: NSHomeDirectory()
                        .appending("/.codex/.codex-global-state.json")
                )),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let atomState = root["electron-persisted-atom-state"] as? [String: Any]
        else {
            return nil
        }

        // Check per-thread heartbeat permissions (most authoritative for Desktop threads).
        // CLI-only sessions (e.g. agentloop) are not present here; their approval policy
        // is signalled by permission_mode=bypassPermissions in the hook payload instead.
        if let permsMap = atomState["heartbeat-thread-permissions-by-id"] as? [String: Any],
            let entry = permsMap[threadId] as? [String: Any],
            let policy = entry["approvalPolicy"] as? String
        {
            return policy
        }

        return nil
    }

    private func handleServerRequest(id: String, method: String, params: [String: Any]) async {
        switch method {
        case "item/commandExecution/requestApproval":
            let threadId = (params["threadId"] as? String) ?? (params["conversationId"] as? String) ?? ""
            guard !threadId.isEmpty else { return }

            let command = ((params["command"] as? [String]) ?? []).joined(separator: " ")

            if !MacIslandProductPolicy.monitorOnly && isAutoApproveThread(threadId) {
                await sendResponse(id: id, result: ["decision": "accept"])
                return
            }

            let cwd = params["cwd"] as? String
            let reason = params["reason"] as? String
            let intervention = SessionIntervention(
                id: id,
                kind: .approval,
                title: "Approve Command",
                message: reason ?? (command.isEmpty ? "Codex wants to run a terminal command." : command),
                options: [],
                questions: [],
                supportsSessionScope: true,
                metadata: [
                    "command": command,
                    "cwd": cwd ?? "",
                ]
            )

            pendingRequestsByThread[threadId] = PendingRequest(
                requestId: id,
                threadId: threadId,
                kind: .commandApproval,
                intervention: intervention,
                requestedPermissions: nil
            )

            await SessionStore.shared.upsertCodexSession(
                sessionId: threadId,
                name: nil,
                preview: command.isEmpty ? reason : command,
                cwd: cwd,
                phase: .waitingForApproval(
                    PermissionContext(
                        toolUseId: params["callId"] as? String ?? id,
                        toolName: "exec_command",
                        toolInput: nil,
                        receivedAt: Date()
                    )),
                intervention: intervention
            )

        case "item/fileChange/requestApproval":
            guard let threadId = params["threadId"] as? String else { return }
            let reason = params["reason"] as? String
            let grantRoot = params["grantRoot"] as? String

            if !MacIslandProductPolicy.monitorOnly && isAutoApproveThread(threadId) {
                await sendResponse(id: id, result: ["decision": "accept"])
                return
            }

            let intervention = SessionIntervention(
                id: id,
                kind: .approval,
                title: "Approve File Changes",
                message: reason ?? grantRoot ?? "Codex wants to modify files in this workspace.",
                options: [],
                questions: [],
                supportsSessionScope: true,
                metadata: [
                    "grantRoot": grantRoot ?? ""
                ]
            )

            pendingRequestsByThread[threadId] = PendingRequest(
                requestId: id,
                threadId: threadId,
                kind: .fileApproval,
                intervention: intervention,
                requestedPermissions: nil
            )

            await SessionStore.shared.upsertCodexSession(
                sessionId: threadId,
                name: nil,
                preview: reason ?? grantRoot,
                cwd: nil,
                phase: .waitingForApproval(
                    PermissionContext(
                        toolUseId: params["itemId"] as? String ?? id,
                        toolName: "file_change",
                        toolInput: nil,
                        receivedAt: Date()
                    )),
                intervention: intervention
            )

        case "item/permissions/requestApproval":
            guard let threadId = params["threadId"] as? String else { return }
            let permissions = params["permissions"] as? [String: Any] ?? [:]
            let reason = params["reason"] as? String
            let message = reason ?? permissionSummary(permissions)

            if !MacIslandProductPolicy.monitorOnly && isAutoApproveThread(threadId) {
                await sendResponse(
                    id: id,
                    result: [
                        "permissions": permissions,
                        "scope": "session",
                    ])
                return
            }

            let intervention = SessionIntervention(
                id: id,
                kind: .approval,
                title: "Approve Permissions",
                message: message,
                options: [],
                questions: [],
                supportsSessionScope: true,
                metadata: [:]
            )

            pendingRequestsByThread[threadId] = PendingRequest(
                requestId: id,
                threadId: threadId,
                kind: .permissionsApproval,
                intervention: intervention,
                requestedPermissions: permissions
            )

            await SessionStore.shared.upsertCodexSession(
                sessionId: threadId,
                name: nil,
                preview: message,
                cwd: nil,
                phase: .waitingForApproval(
                    PermissionContext(
                        toolUseId: params["itemId"] as? String ?? id,
                        toolName: "permissions_request",
                        toolInput: nil,
                        receivedAt: Date()
                    )),
                intervention: intervention
            )

        case "item/tool/requestUserInput":
            guard let threadId = params["threadId"] as? String else { return }
            let questions = Self.parseQuestions(params["questions"] as? [[String: Any]] ?? [])
            let prompt = questions.first?.prompt ?? "Codex needs your input."
            let intervention = SessionIntervention(
                id: id,
                kind: .question,
                title: "Codex Needs Input",
                message: prompt,
                options: questions.first?.options ?? [],
                questions: questions,
                supportsSessionScope: false,
                metadata: [
                    "turnId": params["turnId"] as? String ?? "",
                    "itemId": params["itemId"] as? String ?? "",
                ]
            )

            pendingRequestsByThread[threadId] = PendingRequest(
                requestId: id,
                threadId: threadId,
                kind: .userInput,
                intervention: intervention,
                requestedPermissions: nil
            )

            await SessionStore.shared.upsertCodexSession(
                sessionId: threadId,
                name: nil,
                preview: prompt,
                cwd: nil,
                phase: .waitingForInput,
                intervention: intervention
            )

        default:
            break
        }
    }

    private func sendRequest(method: String, params: Any) async throws -> [String: Any] {
        guard let websocket else {
            throw NSError(
                domain: "CodexAppServer", code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Websocket not connected"
                ])
        }

        let token = recovery.generation
        guard recovery.accepts(token) else { throw CancellationError() }
        requestSequence += 1
        let id = String(requestSequence)
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]

        let message = try Self.webSocketTextMessage(from: payload)

        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[id] = PendingResponse(method: method, continuation: continuation)
            let timeout = requestTimeout
            requestTimeouts[id] = Task { [weak self] in
                do { try await Task.sleep(for: timeout) } catch { return }
                await self?.requestTimedOut(id: id, token: token)
            }
            Task {
                do {
                    try await websocket.send(.string(message))
                } catch {
                    requestTimeouts.removeValue(forKey: id)?.cancel()
                    if let response = pendingResponses.removeValue(forKey: id) {
                        response.continuation.resume(throwing: error)
                    }
                    if recovery.accepts(token), self.websocket === websocket, recovery.health.phase == .connected {
                        connectionFailed(token: token, reason: .connectionLost)
                    }
                }
            }
        }
    }

    private func requestTimedOut(id: String, token: UInt64) {
        guard recovery.accepts(token), let response = pendingResponses.removeValue(forKey: id) else { return }
        requestTimeouts.removeValue(forKey: id)
        response.continuation.resume(throwing: URLError(.timedOut))
        connectionFailed(token: token, reason: .requestTimedOut)
    }

    private func sendResponse(id: String, result: [String: Any]) async {
        guard !MacIslandProductPolicy.monitorOnly else { return }
        guard let websocket else { return }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result,
        ]

        guard let message = try? Self.webSocketTextMessage(from: payload) else {
            return
        }

        do {
            try await websocket.send(.string(message))
        } catch {
            logger.error("Failed to send Codex response: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func ingestThreadList(_ response: [String: Any], token: UInt64) async {
        guard recovery.accepts(token) else { return }
        guard let data = response["data"] as? [[String: Any]] else { return }
        let visibleThreads = data.filter { !Self.shouldIgnoreAuxiliaryThread($0) }
        lastThreadDiagnostics = visibleThreads.map(Self.makeThreadDiagnosticsSnapshot(from:))
        logger.info(
            "Codex thread list received count=\(data.count, privacy: .public) filtered=\(data.count - visibleThreads.count, privacy: .public)"
        )
        for thread in visibleThreads {
            guard recovery.accepts(token) else { return }
            await ingestThread(thread)
        }
        guard recovery.accepts(token) else { return }
        await recoverRecentNotLoadedThreads(visibleThreads, token: token)
    }

    private func recoverRecentNotLoadedThreads(_ threads: [[String: Any]], token: UInt64) async {
        let referenceDate = Date()

        for thread in threads {
            guard recovery.accepts(token) else { return }
            guard let threadId = thread["id"] as? String,
                let version = Self.notLoadedRecoveryVersion(
                    from: thread,
                    referenceDate: referenceDate
                ),
                recoveredNotLoadedThreadVersions[threadId] != version
            else {
                continue
            }

            recoveredNotLoadedThreadVersions[threadId] = version
            let clientInfo = makeClientInfo(from: thread, threadId: threadId)
            // thread/read intentionally preserves notLoaded for stored threads.
            // The rollout is the cross-process source of truth when VS Code owns
            // the live app-server instance.
            let snapshot = await rolloutReader(threadId, thread["cwd"] as? String ?? "/", clientInfo)

            guard recovery.accepts(token), recoveredNotLoadedThreadVersions[threadId] == version else {
                continue
            }
            guard let snapshot else {
                recoveredNotLoadedThreadVersions.removeValue(forKey: threadId)
                logger.debug(
                    "Codex notLoaded rollout recovery unavailable thread=\(threadId, privacy: .public)"
                )
                continue
            }

            await SessionStore.shared.syncCodexThreadSnapshot(snapshot)
            logger.debug(
                "Codex notLoaded rollout recovered thread=\(threadId, privacy: .public) phase=\(String(describing: snapshot.phase), privacy: .public)"
            )
        }
    }

    nonisolated static func notLoadedRecoveryVersion(
        from thread: [String: Any],
        referenceDate: Date = Date()
    ) -> String? {
        guard (thread["status"] as? [String: Any])?["type"] as? String == "notLoaded" else {
            return nil
        }

        let updatedAt = date(fromUnixTimestamp: thread["updatedAt"])
        let recencyAt = date(fromUnixTimestamp: thread["recencyAt"])
        guard let activityAt = [updatedAt, recencyAt].compactMap({ $0 }).max() else {
            return nil
        }

        let activityAge = referenceDate.timeIntervalSince(activityAt)
        guard activityAge >= -maximumFutureActivitySkew,
            activityAge <= notLoadedRecoveryWindow
        else {
            return nil
        }

        return [
            updatedAt.map { String($0.timeIntervalSince1970) } ?? "missing",
            recencyAt.map { String($0.timeIntervalSince1970) } ?? "missing",
        ].joined(separator: "|")
    }

    private static func threadListRequestParams(limit: Int = 30) -> [String: Any] {
        [
            "archived": false,
            "limit": limit,
            "sortKey": "updated_at",
        ]
    }

    private func ingestThread(_ thread: [String: Any]) async {
        guard let threadId = thread["id"] as? String else { return }
        if Self.shouldIgnoreAuxiliaryThread(thread) {
            logger.notice("Ignoring auxiliary Codex thread=\(threadId, privacy: .public)")
            recoveredNotLoadedThreadVersions.removeValue(forKey: threadId)
            removeThreadDiagnostics(threadId: threadId)
            return
        }
        if (thread["status"] as? [String: Any])?["type"] as? String != "notLoaded" {
            recoveredNotLoadedThreadVersions.removeValue(forKey: threadId)
        }

        // Cache approvalMode from app-server data so approval-policy checks
        // don't have to re-read the global state file on every request.
        let rawMode = thread["approvalMode"] as? String ?? thread["approval_mode"] as? String
        if let mode = rawMode {
            threadApprovalModes[threadId] = mode
        }
        let name = thread["name"] as? String
        let preview = thread["preview"] as? String
        let cwd = thread["cwd"] as? String
        let clientInfo = makeClientInfo(from: thread, threadId: threadId)
        let phase = phaseFromCodexStatus(
            thread["status"] as? [String: Any],
            threadId: threadId,
            intervention: pendingRequestsByThread[threadId]?.intervention
        )
        let diagnostics = Self.makeThreadDiagnosticsSnapshot(from: thread)
        let lifecycleDates = Self.threadLifecycleDates(from: thread)
        recordThreadDiagnostics(diagnostics)
        let pathPresent = (thread["path"] as? String)?.isEmpty == false

        logger.info(
            "Codex ingest thread=\(threadId, privacy: .public) phase=\(String(describing: phase), privacy: .public) namePresent=\(name?.isEmpty == false, privacy: .public) previewPresent=\(preview?.isEmpty == false, privacy: .public) cwdPresent=\(cwd?.isEmpty == false, privacy: .public) pathPresent=\(pathPresent, privacy: .public) ephemeral=\(diagnostics.isEphemeral, privacy: .public) placeholderCandidate=\(diagnostics.placeholderCandidate, privacy: .public)"
        )
        if diagnostics.placeholderCandidate {
            logger.notice("Codex ingest placeholder candidate thread=\(threadId, privacy: .public)")
        }

        await SessionStore.shared.upsertCodexSession(
            sessionId: threadId,
            name: name,
            preview: preview,
            cwd: cwd,
            phase: phase,
            intervention: pendingRequestsByThread[threadId]?.intervention,
            clientInfo: clientInfo,
            createdAt: lifecycleDates.createdAt,
            activityAt: lifecycleDates.updatedAt,
            allowSyntheticActivityTimestamp: false
        )
    }

    private func recordThreadDiagnostics(_ snapshot: ThreadDiagnosticsSnapshot) {
        if let existingIndex = lastThreadDiagnostics.firstIndex(where: { $0.threadId == snapshot.threadId }) {
            lastThreadDiagnostics[existingIndex] = snapshot
        } else {
            lastThreadDiagnostics.insert(snapshot, at: 0)
        }
    }

    private func removeThreadDiagnostics(threadId: String) {
        lastThreadDiagnostics.removeAll { $0.threadId == threadId }
    }

    private static func makeThreadDiagnosticsSnapshot(from thread: [String: Any]) -> ThreadDiagnosticsSnapshot {
        func normalize(_ text: String?) -> String? {
            guard let text else { return nil }
            let collapsed =
                text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return collapsed.isEmpty ? nil : collapsed
        }

        let threadId = thread["id"] as? String ?? "unknown"
        let name = normalize(thread["name"] as? String)
        let preview = normalize(thread["preview"] as? String)
        let cwd = normalize(thread["cwd"] as? String)
        let path = normalize(thread["path"] as? String)
        let statusType = (thread["status"] as? [String: Any])?["type"] as? String
        let isEphemeral = thread["ephemeral"] as? Bool ?? false
        let updatedAt = Self.threadLifecycleDates(from: thread).updatedAt
        let placeholderCandidate =
            !isEphemeral
            && (name?.isEmpty != false)
            && (preview?.isEmpty != false)
            && (path?.isEmpty != false)
            && (statusType != "active"
                || {
                    guard let updatedAt else { return false }
                    return Date().timeIntervalSince(updatedAt) >= 60
                }())

        return ThreadDiagnosticsSnapshot(
            threadId: threadId,
            name: name,
            preview: preview,
            cwd: cwd,
            path: path,
            statusType: statusType,
            isEphemeral: isEphemeral,
            updatedAt: updatedAt,
            placeholderCandidate: placeholderCandidate
        )
    }

    private static func shouldIgnoreAuxiliaryThread(_ thread: [String: Any]) -> Bool {
        CodexAuxiliaryHookFilter.isCodexMemoryMaintenanceThread(
            cwd: thread["cwd"] as? String,
            title: thread["name"] as? String,
            preview: thread["preview"] as? String,
            metadata: [
                "session_file_path": sanitizedThreadText(thread["sessionFilePath"] as? String)
                    ?? sanitizedThreadText(thread["rolloutPath"] as? String)
                    ?? sanitizedThreadText(thread["path"] as? String)
                    ?? "",
                "thread_source": sanitizedThreadText(thread["threadSource"] as? String)
                    ?? sanitizedThreadText(thread["source"] as? String)
                    ?? "",
            ]
        )
    }

    private static func sanitizedThreadText(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed =
            text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }

    nonisolated static func rolloutPath(from thread: [String: Any]) -> String? {
        [
            thread["rolloutPath"] as? String,
            thread["sessionFilePath"] as? String,
            thread["rollout_path"] as? String,
            thread["path"] as? String,
        ]
        .compactMap(sanitizedThreadText(_:))
        .first(where: { $0.hasSuffix(".jsonl") })
    }

    private func parseThreadSnapshot(_ thread: [String: Any]) -> CodexThreadSnapshot? {
        guard let threadId = thread["id"] as? String else { return nil }
        guard !Self.shouldIgnoreAuxiliaryThread(thread) else { return nil }

        // Keep the approval-mode cache fresh: thread/read and thread/list both
        // call this path, so any policy change made in Codex Desktop will be
        // reflected within the next polling cycle (≤ 30 s).
        if let mode = thread["approvalMode"] as? String ?? thread["approval_mode"] as? String {
            threadApprovalModes[threadId] = mode
        }

        let lifecycleDates = Self.threadLifecycleDates(from: thread)
        let createdAt = lifecycleDates.createdAt ?? Date()
        let updatedAt = lifecycleDates.updatedAt ?? createdAt
        let status = thread["status"] as? [String: Any]
        let snapshotClientInfo = makeClientInfo(from: thread, threadId: threadId)
        let phase = phaseFromCodexStatus(
            status,
            threadId: threadId,
            intervention: pendingRequestsByThread[threadId]?.intervention
        )
        let turns = thread["turns"] as? [[String: Any]] ?? []

        var historyItems: [ChatHistoryItem] = []
        var firstUserMessage: String?
        var lastMessage: String?
        var lastMessageRole: String?
        var lastUserMessageDate: Date?
        var latestUserText: String?
        var latestAgentText: String?
        var latestAgentPhase: String?
        var latestFinalText: String?
        var latestFinalPhase: String?
        var latestTurnId: String?
        var inferredIntervention: SessionIntervention?
        var itemOffset: TimeInterval = 0
        let subagentMetadata = parseSubagentMetadata(from: thread)

        for (turnIndex, turn) in turns.enumerated() {
            if turnIndex == turns.count - 1 {
                latestTurnId = turn["id"] as? String
            }

            let items = turn["items"] as? [[String: Any]] ?? []
            for item in items {
                itemOffset += 1
                let timestamp = createdAt.addingTimeInterval(itemOffset)
                let itemId = item["id"] as? String ?? UUID().uuidString

                switch item["type"] as? String {
                case "userMessage":
                    let text = parseUserMessageText(item["content"] as? [[String: Any]] ?? [])
                    guard let text else { continue }

                    if firstUserMessage == nil {
                        firstUserMessage = text
                    }
                    latestUserText = text
                    lastMessage = text
                    lastMessageRole = "user"
                    lastUserMessageDate = timestamp
                    historyItems.append(ChatHistoryItem(id: itemId, type: .user(text), timestamp: timestamp))

                case "agentMessage":
                    guard let text = sanitizedText(item["text"] as? String) else { continue }
                    let messagePhase = item["phase"] as? String
                    latestAgentText = text
                    latestAgentPhase = messagePhase
                    if messagePhase != "commentary" {
                        latestFinalText = text
                        latestFinalPhase = messagePhase
                    }

                    lastMessage = text
                    lastMessageRole = "assistant"
                    let type: ChatHistoryItemType = messagePhase == "commentary" ? .thinking(text) : .assistant(text)
                    historyItems.append(ChatHistoryItem(id: itemId, type: type, timestamp: timestamp))

                case "mcpToolCall":
                    let server = sanitizedText(item["server"] as? String) ?? "unknown"
                    let tool = sanitizedText(item["tool"] as? String) ?? "tool"
                    let statusValue = item["status"] as? String
                    let toolStatus: ToolStatus
                    switch statusValue {
                    case "completed":
                        toolStatus = .success
                    case "failed":
                        toolStatus = .error
                    default:
                        toolStatus = .running
                    }
                    let input = stringifyDictionary(item["arguments"] as? [String: Any] ?? [:])
                    let result = normalizedToolResultString(item["result"])
                    let toolName = "mcp__\(server)__\(tool)"
                    historyItems.append(
                        ChatHistoryItem(
                            id: itemId,
                            type: .toolCall(
                                ToolCallItem(
                                    name: toolName,
                                    input: input,
                                    status: toolStatus,
                                    result: result,
                                    structuredResult: nil,
                                    subagentTools: []
                                )),
                            timestamp: timestamp
                        ))
                    if toolStatus == .running, snapshotClientInfo.kind == .codexCLI {
                        inferredIntervention = SessionIntervention(
                            id: "mcp-pending-\(server)-\(tool)",
                            kind: .question,
                            title: "MCP Tool Approval Needed",
                            message: "Allow the \(server) MCP server to run tool \"\(tool)\"?",
                            options: [],
                            questions: [],
                            supportsSessionScope: false,
                            metadata: [
                                "responseMode": "external_only",
                                "source": "app_server_pending_mcp",
                                "server": server,
                                "toolName": tool,
                            ]
                        )
                    }

                default:
                    continue
                }
            }
        }

        let preview = sanitizedText(thread["preview"] as? String)
        let summary = sanitizedText(thread["name"] as? String) ?? preview ?? firstUserMessage
        let conversationInfo = ConversationInfo(
            summary: summary,
            lastMessage: lastMessage,
            lastMessageRole: lastMessageRole,
            lastToolName: nil,
            firstUserMessage: firstUserMessage,
            lastUserMessageDate: lastUserMessageDate
        )

        return CodexThreadSnapshot(
            threadId: threadId,
            name: sanitizedText(thread["name"] as? String),
            preview: preview,
            cwd: (thread["cwd"] as? String) ?? "/",
            modelName: sanitizedText(thread["model"] as? String),
            parentThreadId: subagentMetadata?.parentThreadId,
            subagentDepth: subagentMetadata?.depth,
            subagentNickname: subagentMetadata?.nickname,
            subagentRole: subagentMetadata?.role,
            clientInfo: snapshotClientInfo,
            intervention: inferredIntervention,
            createdAt: createdAt,
            updatedAt: updatedAt,
            phase: inferredIntervention != nil ? .waitingForInput : phase,
            historyItems: historyItems,
            conversationInfo: conversationInfo,
            latestTurnId: latestTurnId,
            latestResponseText: latestFinalText ?? latestAgentText ?? preview,
            latestResponsePhase: latestFinalPhase ?? latestAgentPhase,
            latestUserText: latestUserText
        )
    }

    private func parseSubagentMetadata(from thread: [String: Any]) -> ParsedSubagentMetadata? {
        let topLevelNickname =
            sanitizedText(thread["agentNickname"] as? String)
            ?? sanitizedText(thread["agent_nickname"] as? String)
        let topLevelRole =
            sanitizedText(thread["agentRole"] as? String)
            ?? sanitizedText(thread["agent_role"] as? String)
        let topLevelParent =
            sanitizedText(thread["parentThreadId"] as? String)
            ?? sanitizedText(thread["parent_thread_id"] as? String)
            ?? sanitizedText(thread["forkedFromId"] as? String)
            ?? sanitizedText(thread["forked_from_id"] as? String)
        let topLevelDepth = intValue(thread["subagentDepth"]) ?? intValue(thread["depth"])

        guard let source = thread["source"] as? [String: Any] else {
            guard topLevelParent != nil || topLevelDepth != nil || topLevelNickname != nil || topLevelRole != nil else {
                return nil
            }
            return ParsedSubagentMetadata(
                parentThreadId: topLevelParent,
                depth: topLevelDepth,
                nickname: topLevelNickname,
                role: topLevelRole
            )
        }

        let subagent = source["subagent"] as? [String: Any]
        let threadSpawn = subagent?["thread_spawn"] as? [String: Any]

        let parentThreadId = sanitizedText(threadSpawn?["parent_thread_id"] as? String) ?? topLevelParent
        let depth = intValue(threadSpawn?["depth"]) ?? topLevelDepth
        let nickname = sanitizedText(threadSpawn?["agent_nickname"] as? String) ?? topLevelNickname
        let role = sanitizedText(threadSpawn?["agent_role"] as? String) ?? topLevelRole

        guard parentThreadId != nil || depth != nil || nickname != nil || role != nil else {
            return nil
        }

        return ParsedSubagentMetadata(
            parentThreadId: parentThreadId,
            depth: depth,
            nickname: nickname,
            role: role
        )
    }

    private func phaseFromCodexStatus(
        _ status: [String: Any]?,
        threadId: String,
        intervention: SessionIntervention?
    ) -> SessionPhase {
        if intervention?.kind == .approval {
            return .waitingForApproval(
                PermissionContext(
                    toolUseId: intervention?.id ?? "codex-approval-\(threadId)",
                    toolName: intervention?.title ?? "approval",
                    toolInput: nil,
                    receivedAt: Date()
                ))
        }

        guard let type = status?["type"] as? String else {
            if intervention?.kind == .question {
                return .waitingForInput
            }
            return .idle
        }

        if type == "active" {
            let flags = status?["activeFlags"] as? [String] ?? []
            if flags.contains("waitingOnApproval") {
                return .waitingForApproval(
                    PermissionContext(
                        toolUseId: intervention?.id ?? "codex-approval-\(threadId)",
                        toolName: intervention?.title ?? "approval",
                        toolInput: nil,
                        receivedAt: Date()
                    ))
            }
            if flags.contains("waitingOnUserInput") {
                return .waitingForInput
            }
            return .processing
        }

        if type == "systemError" {
            return .idle
        }

        return .idle
    }

    static func guardianReviewIntervention(from params: [String: Any]) -> SessionIntervention? {
        func normalized(_ value: String?) -> String? {
            guard let value else { return nil }
            let collapsed =
                value
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return collapsed.isEmpty ? nil : collapsed
        }

        guard let review = params["review"] as? [String: Any],
            (review["status"] as? String) == "inProgress",
            let action = params["action"] as? [String: Any],
            let actionType = action["type"] as? String
        else {
            return nil
        }

        let title: String
        let message: String
        var metadata: [String: String] = [
            "responseMode": "external_only",
            "source": "guardian_review",
            "guardianActionType": actionType,
        ]

        switch actionType {
        case "mcpToolCall":
            let server = normalized(action["server"] as? String) ?? "unknown"
            let toolName = normalized(action["toolName"] as? String) ?? "tool"
            let toolTitle = normalized(action["toolTitle"] as? String)
            title = "MCP Tool Approval Needed"
            message = "Allow the \(server) MCP server to run tool \"\(toolTitle ?? toolName)\"?"
            metadata["server"] = server
            metadata["toolName"] = toolName
            if let toolTitle {
                metadata["toolTitle"] = toolTitle
            }

        case "command":
            let command = normalized(action["command"] as? String) ?? "command"
            title = "Command Approval Needed"
            message = "Allow command:\n\(command)"
            metadata["command"] = command

        case "execve":
            let program = normalized(action["program"] as? String) ?? "command"
            let argv = (action["argv"] as? [String] ?? []).joined(separator: " ")
            title = "Command Approval Needed"
            message = argv.isEmpty ? "Allow command:\n\(program)" : "Allow command:\n\(program) \(argv)"
            metadata["command"] = message

        case "applyPatch":
            let cwd = normalized(action["cwd"] as? String) ?? ""
            let files = (action["files"] as? [String] ?? []).joined(separator: "\n")
            title = "Patch Approval Needed"
            message =
                files.isEmpty
                ? "Allow file changes\(cwd.isEmpty ? "" : " in \(cwd)")?"
                : "Allow file changes to:\n\(files)"
            if !cwd.isEmpty {
                metadata["cwd"] = cwd
            }

        case "networkAccess":
            let target = normalized(action["target"] as? String) ?? "network target"
            title = "Network Approval Needed"
            message = "Allow network access to \(target)?"
            metadata["target"] = target

        default:
            return nil
        }

        return SessionIntervention(
            id: (params["targetItemId"] as? String) ?? UUID().uuidString,
            kind: .question,
            title: title,
            message: message,
            options: [],
            questions: [],
            supportsSessionScope: false,
            metadata: metadata
        )
    }

    nonisolated static func parseQuestions(_ rawQuestions: [[String: Any]]) -> [SessionInterventionQuestion] {
        rawQuestions.map { question in
            let options = (question["options"] as? [[String: Any]] ?? []).enumerated().map { index, option in
                SessionInterventionOption(
                    id: option["label"] as? String ?? "option-\(index)",
                    title: option["label"] as? String ?? "Option \(index + 1)",
                    detail: option["description"] as? String
                )
            }

            return SessionInterventionQuestion(
                id: question["id"] as? String ?? UUID().uuidString,
                header: question["header"] as? String ?? "Question",
                prompt: question["question"] as? String ?? "",
                detail: nil,
                options: options,
                allowsMultiple: question["isMultiple"] as? Bool
                    ?? question["allowsMultiple"] as? Bool
                    ?? question["multiSelect"] as? Bool
                    ?? question["multiple"] as? Bool
                    ?? false,
                allowsOther: true,
                isSecret: question["isSecret"] as? Bool ?? false
            )
        }
    }

    private func makeClientInfo(from thread: [String: Any], threadId: String) -> SessionClientInfo {
        let origin =
            sanitizedText(thread["origin"] as? String)
            ?? sanitizedText(thread["clientOrigin"] as? String)
        let originator =
            sanitizedText(thread["originator"] as? String)
            ?? sanitizedText(thread["clientOriginator"] as? String)
        let threadSource =
            sanitizedText(thread["threadSource"] as? String)
            ?? sanitizedText(thread["source"] as? String)
            ?? sanitizedText(thread["sessionStartSource"] as? String)
        let sessionFilePath = Self.rolloutPath(from: thread)

        let resolvedOrigin = origin ?? "desktop"

        let inferredKind: SessionClientKind
        if resolvedOrigin.localizedCaseInsensitiveContains("cli") {
            inferredKind = .codexCLI
        } else {
            inferredKind = .codexApp
        }

        let defaultInfo =
            inferredKind == .codexApp
            ? SessionClientInfo(
                kind: .codexApp,
                profileID: "codex-app",
                name: resolvedClientName ?? "Codex App",
                bundleIdentifier: resolvedClientBundleIdentifier ?? "com.openai.codex",
                launchURL: SessionClientInfo.appLaunchURL(
                    bundleIdentifier: resolvedClientBundleIdentifier ?? "com.openai.codex",
                    sessionId: threadId
                ),
                origin: "desktop"
            )
            : SessionClientInfo(kind: .codexCLI, profileID: "codex-cli", name: "Codex CLI")

        return defaultInfo.merged(
            with: SessionClientInfo(
                kind: inferredKind,
                profileID: inferredKind == .codexApp ? "codex-app" : "codex-cli",
                name: originator ?? defaultInfo.name,
                bundleIdentifier: inferredKind == .codexApp ? defaultInfo.bundleIdentifier : nil,
                launchURL: inferredKind == .codexApp ? defaultInfo.launchURL : nil,
                origin: resolvedOrigin,
                originator: originator,
                threadSource: threadSource,
                sessionFilePath: sessionFilePath
            ))
    }

    private func permissionSummary(_ permissions: [String: Any]) -> String {
        var parts: [String] = []

        if let fileSystem = permissions["fileSystem"] as? [String: Any] {
            if let read = fileSystem["read"] as? [String], !read.isEmpty {
                parts.append("Read: \(read.joined(separator: ", "))")
            }
            if let write = fileSystem["write"] as? [String], !write.isEmpty {
                parts.append("Write: \(write.joined(separator: ", "))")
            }
        }

        if let network = permissions["network"] as? [String: Any],
            let enabled = network["enabled"] as? Bool
        {
            parts.append(enabled ? "Network access requested" : "Network access disabled")
        }

        return parts.isEmpty ? "Codex requested extra permissions." : parts.joined(separator: "\n")
    }

    private func normalizedToolResultString(_ value: Any?) -> String? {
        if let text = sanitizedText(value as? String) {
            return text
        }
        guard let value,
            JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return text
    }

    private func stringifyDictionary(_ value: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, raw) in value {
            if let text = sanitizedText(raw as? String) {
                result[key] = text
            } else if JSONSerialization.isValidJSONObject(raw),
                let data = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]),
                let text = String(data: data, encoding: .utf8)
            {
                result[key] = text
            } else {
                result[key] = String(describing: raw)
            }
        }
        return result
    }

    private func parseUserMessageText(_ content: [[String: Any]]) -> String? {
        let fragments = content.compactMap { item -> String? in
            switch item["type"] as? String {
            case "text":
                return sanitizedText(item["text"] as? String)
            case "image":
                return "[Image]"
            case "localImage":
                if let path = item["path"] as? String {
                    return "[Image] \(URL(fileURLWithPath: path).lastPathComponent)"
                }
                return "[Image]"
            case "mention", "skill":
                return sanitizedText(item["name"] as? String)
            default:
                return nil
            }
        }

        guard !fragments.isEmpty else { return nil }
        return sanitizedText(fragments.joined(separator: "\n"))
    }

    private func sanitizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed =
            text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return collapsed.isEmpty ? nil : collapsed
    }

    static func threadLifecycleDates(from thread: [String: Any]) -> (createdAt: Date?, updatedAt: Date?) {
        (
            createdAt: date(fromUnixTimestamp: thread["createdAt"]),
            updatedAt: date(fromUnixTimestamp: thread["updatedAt"])
        )
    }

    private static func date(fromUnixTimestamp rawValue: Any?) -> Date? {
        ObservedNumber.unixDate(rawValue)
    }

    static func webSocketTextMessage(from payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let message = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "CodexAppServer", code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to encode websocket payload as UTF-8 text"
                ])
        }
        return message
    }

    private func stringify(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return String(describing: value)
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    private static func resolveCodexExecutable() async -> String? {
        let applications = await CodexExecutableResolver.preferredApplications()
        return CodexExecutableResolver.resolve(
            preferredApplications: applications,
            applicationDirectories: [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            ],
            searchPath: Foundation.ProcessInfo.processInfo.environment["PATH"] ?? ""
        )
    }

    private static func bundleIdentifier(forCodexExecutable executable: String) -> String? {
        let executableURL = URL(fileURLWithPath: executable)
        guard executableURL.path.contains(".app/") else { return nil }
        let appPath = executableURL.path.components(separatedBy: "/Contents/").first ?? ""
        guard !appPath.isEmpty else { return nil }
        return Bundle(url: URL(fileURLWithPath: appPath))?.bundleIdentifier
    }

    private static func clientName(forCodexExecutable executable: String) -> String? {
        let executableURL = URL(fileURLWithPath: executable)
        guard executableURL.path.contains(".app/") else { return nil }
        let appPath = executableURL.path.components(separatedBy: "/Contents/").first ?? ""
        guard !appPath.isEmpty,
            let bundle = Bundle(url: URL(fileURLWithPath: appPath))
        else {
            return nil
        }

        return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
    }

}
