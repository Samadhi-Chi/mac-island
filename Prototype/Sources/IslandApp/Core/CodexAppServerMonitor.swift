import Foundation
import IslandShared

actor CodexAppServerMonitor {
    private let sessionStore: SessionStore
    private let noteDidChange: @MainActor (String) -> Void
    private var process: Process?
    private var websocket: (any CodexMonitorTransport)?
    private var receiveTask: Task<Void, Never>?
    private static let maximumWebSocketMessageSize = 32 * 1024 * 1024

    init(
        sessionStore: SessionStore,
        noteDidChange: @escaping @MainActor (String) -> Void
    ) {
        self.sessionStore = sessionStore
        self.noteDidChange = noteDidChange
    }

    func start() async {
        if let process, !process.isRunning { self.process = nil }
        guard process == nil else { return }
        guard let executable = resolveCodexExecutable() else {
            await noteDidChange("Codex CLI not found, using hook-only mode")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--listen", "stdio://", "-c", "analytics.enabled=false"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            self.process = process
            let transport = CodexStdioTransport(input: input.fileHandleForWriting, output: output.fileHandleForReading)
            websocket = transport
            transport.resume()
            receiveLoop()
            let request: [String: Any] = [
                "id": "initialize", "method": "initialize",
                "params": [
                    "clientInfo": ["name": "IslandPrototype", "title": "Island Prototype", "version": "0.1.0"]
                ],
            ]
            try await transport.send(.data(JSONSerialization.data(withJSONObject: request)))
        } catch {
            await noteDidChange("Codex app-server unavailable: \(error.localizedDescription)")
        }
    }

    func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        websocket?.cancel(with: .goingAway, reason: nil)
        websocket = nil
        if let process, process.isRunning { process.terminate() }
        // Retain ownership until exit; start() must not overlap children.
    }

    func submit(response: InterventionDecision, for request: InterventionRequest) async throws {
        guard let websocket else { return }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": request.kind == .approval ? "approval/submit" : "question/submit",
            "params": [
                "requestId": request.id.uuidString,
                "threadId": request.sessionID,
                "decision": decisionPayload(response),
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try await websocket.send(.data(data))
    }

    private func receiveLoop() {
        guard let transport = websocket else { return }
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await transport.receive()
                    guard let self, await self.isCurrent(transport), !Task.isCancelled else { return }
                    await self.handle(message)
                } catch {
                    guard let self, await self.isCurrent(transport) else { return }
                    await self.stop()
                    await self.noteDidChange("Codex observer disconnected")
                    return
                }
            }
        }
    }

    private func isCurrent(_ transport: any CodexMonitorTransport) -> Bool { websocket === transport }

    private func handle(_ message: URLSessionWebSocketTask.Message) async {
        let data: Data
        switch message {
        case .data(let raw):
            data = raw
        case .string(let text):
            data = Data(text.utf8)
        @unknown default:
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if json["id"] as? String == "initialize", json["result"] != nil {
            try? await websocket?.send(.string(#"{"method":"initialized"}"#))
            await noteDidChange("Codex observer connected")
            return
        }
        guard let method = json["method"] as? String,
            let params = json["params"] as? [String: Any]
        else {
            return
        }

        if method == "thread/status/changed" {
            let threadID = (params["threadId"] as? String) ?? "codex:unknown"
            let status = statusFromCodex(params["status"] as? [String: Any])
            await sessionStore.ingestCodexStatus(
                sessionID: threadID,
                title: params["title"] as? String,
                preview: params["preview"] as? String,
                status: status,
                metadata: params.compactMapValues { value in
                    if let string = value as? String { return string }
                    return nil
                }
            )
            await noteDidChange("Codex session updated")
        }
    }

    private func statusFromCodex(_ status: [String: Any]?) -> SessionStatus {
        guard let type = status?["type"] as? String else {
            return SessionStatus(kind: .active)
        }
        if type == "active" {
            let flags = status?["activeFlags"] as? [String] ?? []
            if flags.contains("waitingOnApproval") {
                return SessionStatus(kind: .waitingForApproval)
            }
            if flags.contains("waitingOnUserInput") {
                return SessionStatus(kind: .waitingForInput)
            }
            return SessionStatus(kind: .thinking)
        }
        if type == "idle" {
            return SessionStatus(kind: .completed)
        }
        if type == "systemError" {
            return SessionStatus(kind: .error)
        }
        return SessionStatus(kind: .active)
    }

    private func decisionPayload(_ decision: InterventionDecision) -> Any {
        switch decision {
        case .approve:
            return "accept"
        case .approveForSession:
            return "acceptForSession"
        case .deny:
            return "decline"
        case .cancel:
            return "cancel"
        case .answer(let answers):
            return answers
        }
    }

    private func resolveCodexExecutable() -> String? {
        let bundled = "/Applications/Codex.app/Contents/Resources/codex"
        if FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        return ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init)
            .map { "\($0)/codex" }
            .first(where: FileManager.default.isExecutableFile(atPath:))
    }
}
