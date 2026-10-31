//
//  SessionMonitor.swift
//  PingIsland
//
//  MainActor wrapper around SessionStore for UI binding.
//  Publishes SessionState arrays for SwiftUI observation.
//

import AppKit
import Combine
import Foundation

/// One shutdown boundary covers the launch monitor and every window's monitor.
/// Keeping it separate lets lifecycle tests use isolated, synthetic services.
@MainActor
final class SessionMonitoringShutdown {
    static let shared = SessionMonitoringShutdown()

    // Only weak registrations are released here; avoid the Swift 6.2
    // isolated-deinit back-deployment crash during synchronous teardown.
    nonisolated deinit {}

    private struct Registration {
        weak var lifecycle: SessionMonitoringLifecycle?
    }

    private var registrations: [Registration] = []
    private(set) var hasBegun = false

    func register(_ lifecycle: SessionMonitoringLifecycle) {
        registrations.removeAll { $0.lifecycle == nil }
        registrations.append(Registration(lifecycle: lifecycle))
    }

    func begin() {
        guard !hasBegun else { return }
        hasBegun = true
        for registration in registrations {
            registration.lifecycle?.stop()
        }
    }
}

@MainActor
final class SessionMonitoringLifecycle {
    private let shutdown: SessionMonitoringShutdown
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private(set) var hasStarted = false
    var onStop: (() -> Void)?
    var isApplicationShuttingDown: Bool { shutdown.hasBegun }

    // stop() owns actor-bound cleanup. Releasing these stored references needs
    // no executor hop, including when a window monitor is released synchronously.
    nonisolated deinit {}

    init(shutdown: SessionMonitoringShutdown? = nil) {
        self.shutdown = shutdown ?? .shared
        self.shutdown.register(self)
    }

    func start() -> Bool {
        guard !shutdown.hasBegun, !hasStarted else { return false }
        hasStarted = true
        return true
    }

    /// The second check runs inside the task: quit may precede its first turn.
    /// An actor's already-enqueued start may ignore cancellation, so compensate
    /// after it returns if shutdown overtook that start.
    @discardableResult
    func enqueue(
        _ operation: @escaping @MainActor () async -> Void,
        onStopped: @escaping @MainActor () async -> Void = {}
    ) -> Task<Void, Never>? {
        guard hasStarted, !shutdown.hasBegun else { return nil }
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.tasks[id] = nil }
            guard self.hasStarted, !self.shutdown.hasBegun, !Task.isCancelled else { return }
            await operation()
            if self.shutdown.hasBegun || !self.hasStarted {
                await onStopped()
            }
        }
        tasks[id] = task
        return task
    }

    func stop() {
        hasStarted = false
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        onStop?()
    }
}

@MainActor
class SessionMonitor: ObservableObject {
    @Published var instances: [SessionState] = []
    @Published var pendingInstances: [SessionState] = []
    @Published private(set) var sessionSnapshots: [MacIslandSessionSnapshot] = []
    @Published private(set) var personalAgentObservations: [PersonalAgentObservation] = []
    @Published private(set) var hasEnabledPersonalAgentSources = false
    @Published private(set) var claudeUsageSnapshot: ClaudeUsageSnapshot?
    @Published private(set) var codexUsageSnapshot: CodexUsageSnapshot?
    @Published private(set) var cursorUsageSnapshot: CursorUsageSnapshot?

    nonisolated static var isRunningUnderXCTest: Bool {
        Foundation.ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    nonisolated static func allowsLiveMonitoring(
        environment: [String: String] = Foundation.ProcessInfo.processInfo.environment,
        hasXCTestRuntime: Bool = NSClassFromString("XCTestCase") != nil
    ) -> Bool {
        MacIslandRuntimeEnvironment.allowsLiveIO(environment: environment, hasXCTestRuntime: hasXCTestRuntime)
    }

    private let runtimeCoordinator: any RuntimeCoordinating
    private let monitoringLifecycle = SessionMonitoringLifecycle()
    private var cancellables = Set<AnyCancellable>()
    private var energyCancellable: AnyCancellable?
    var hasStarted: Bool { monitoringLifecycle.hasStarted }
    let recentSessions: RecentSessionIndex
    private var allSessions: [SessionState] = []
    private var localVisibility = LocalSessionVisibilityState()
    private var usageRefreshTask: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?
    private let shouldRefreshUsage: Bool
    private var questionDraftCache = SessionQuestionDraftCache()
    private var telemetryPendingAttentionSessionIDs: Set<String> = []

    init(
        runtimeCoordinator: any RuntimeCoordinating = RuntimeCoordinator.shared,
        observeSharedState: Bool = true,
        recentSessions: RecentSessionIndex? = nil,
        personalAgentObservations: [PersonalAgentObservation] = []
    ) {
        self.personalAgentObservations = personalAgentObservations
        if let fixturePath = Foundation.ProcessInfo.processInfo.environment[MacIslandFixturePlayer.environmentKey],
            !fixturePath.isEmpty
        {
            self.personalAgentObservations =
                (try? MacIslandFixturePlayer.personalAgentObservations(fileURL: URL(fileURLWithPath: fixturePath)))
                ?? []
        }
        self.recentSessions = recentSessions ?? RecentSessionIndex.shared
        self.runtimeCoordinator = runtimeCoordinator
        self.shouldRefreshUsage =
            MacIslandProductPolicy.usageTrackingEnabled
            && Self.allowsLiveMonitoring()
        monitoringLifecycle.onStop = { [weak self] in
            self?.cancelLocalMonitoringWork()
        }
        guard observeSharedState else { return }
        if Self.allowsLiveMonitoring() {
            PersonalAgentMonitor.shared.$observations
                .sink { [weak self] in self?.personalAgentObservations = $0 }
                .store(in: &cancellables)
            PersonalAgentMonitor.shared.$enabled
                .map { !$0.isEmpty }
                .sink { [weak self] in self?.hasEnabledPersonalAgentSources = $0 }
                .store(in: &cancellables)
        }
        if shouldRefreshUsage {
            claudeUsageSnapshot =
                HookInstaller.isManagedClaudeStatusLineConfigured()
                ? UsageSnapshotCacheStore.loadClaude().flatMap { $0.isFresh() ? $0 : nil }
                : nil
            codexUsageSnapshot = UsageSnapshotCacheStore.loadCodex()
            cursorUsageSnapshot = MacIslandProductPolicy.monitorOnly ? nil : UsageSnapshotCacheStore.loadCursor()
        }

        SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateFromSessions(sessions)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .macIslandCodexUsageDidUpdate)
            .receive(on: DispatchQueue.main)
            .compactMap { $0.object as? CodexUsageSnapshot }
            .sink { [weak self] snapshot in
                self?.acceptCodexUsageSnapshot(snapshot)
            }
            .store(in: &cancellables)

        startEnergyAwareMaintenanceLoop()

        InterruptWatcherManager.shared.delegate = self

        AppSettings.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshVisibleSessions()
            }
            .store(in: &cancellables)

        if shouldRefreshUsage {
            refreshUsageState()
        }
    }

    deinit {
        maintenanceTask?.cancel()
        usageRefreshTask?.cancel()
    }

    // MARK: - Monitoring Lifecycle

    func questionDraft(sessionId: String, interventionId: String) -> SessionQuestionFormDraft? {
        questionDraftCache.draft(sessionId: sessionId, interventionId: interventionId)
    }

    func updateQuestionDraft(
        sessionId: String,
        interventionId: String,
        draft: SessionQuestionFormDraft
    ) {
        questionDraftCache.update(
            sessionId: sessionId,
            interventionId: interventionId,
            draft: draft
        )
    }

    func clearQuestionDraft(sessionId: String, interventionId: String) {
        questionDraftCache.clear(sessionId: sessionId, interventionId: interventionId)
    }

    func startMonitoring() {
        // Window previews also call this entrypoint from onAppear. AppDelegate's
        // launch gate alone cannot isolate hosted UI tests or fixture playback.
        guard Self.allowsLiveMonitoring(), monitoringLifecycle.start() else { return }
        PersonalAgentMonitor.shared.acquire(self)
        energyCancellable = EnergyGovernor.shared.$policy
            .map { !$0.allowsFileWatcherRetry }
            .removeDuplicates()
            .sink { [weak self] suspended in
                self?.monitoringLifecycle.enqueue {
                    await CodexReadOnlyClient.shared.setSuspended(suspended)
                }
            }
        if maintenanceTask == nil {
            startEnergyAwareMaintenanceLoop()
        }

        // Periodic liveness sweep: removes sessions whose Claude process has
        // died without delivering SessionEnd, plus garbage-collects sessions
        // already in .ended phase. See SessionStore.startLivenessSweep for
        // details.
        monitoringLifecycle.enqueue {
            await SessionStore.shared.startLivenessSweep()
        } onStopped: {
            await SessionStore.shared.stopLivenessSweep()
        }

        let handleHookEvent: @Sendable (HookEvent) -> Void = { [self] event in
            Task { @MainActor in
                guard !SessionMonitoringShutdown.shared.hasBegun else { return }
                await self.handleIncomingHookEvent(event)
            }
        }

        HookSocketServer.shared.start(
            onEvent: handleHookEvent,
            onPermissionFailure: { sessionId, toolUseId in
                Task {
                    await SessionStore.shared.process(
                        .permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId)
                    )
                }
            }
        )

        monitoringLifecycle.enqueue {
            await CodexReadOnlyClient.shared.startNotifications()
        }

        monitoringLifecycle.enqueue {
            await CursorConversationMonitor.shared.start()
        } onStopped: {
            await CursorConversationMonitor.shared.stop()
        }

        monitoringLifecycle.enqueue {
            let recovered =
                ObservedSessionRecovery.loadOpenCode()
                + ObservedSessionRecovery.loadHermes()
            await SessionStore.shared.restoreObservedSessions(recovered)
        }

        // Mac Island V1 deliberately does not start Claude Desktop discovery,
        // native agent runtimes, or remote/SSH connectors.
    }

    func handleIncomingHookEvent(_ event: HookEvent) async {
        guard
            MacIslandProductPolicy.supportsSession(
                provider: event.provider,
                clientInfo: event.clientInfo
            )
        else { return }

        let effectiveEvent = Self.productSafeHookEvent(event)

        var shouldAutoApprovePermission = false
        if !MacIslandProductPolicy.monitorOnly {
            shouldAutoApprovePermission = await Self.shouldAutoApproveClaudePermission(for: effectiveEvent)
        }

        await SessionStore.shared.process(.hookReceived(effectiveEvent))

        if shouldAutoApprovePermission,
            let approvedToolUseId = await Self.resolvePendingApprovalToolUseId(
                for: effectiveEvent.sessionId, fallback: effectiveEvent.toolUseId)
        {
            if effectiveEvent.ingress == .remoteBridge {
                RemoteConnectorManager.shared.respondToPermission(
                    toolUseId: approvedToolUseId,
                    decision: "approveForSession"
                )
            } else {
                HookSocketServer.shared.respondToPermission(
                    toolUseId: approvedToolUseId,
                    decision: "approveForSession"
                )
            }
            await SessionStore.shared.process(
                .permissionApproved(sessionId: effectiveEvent.sessionId, toolUseId: approvedToolUseId)
            )
            return
        }

        if !MacIslandProductPolicy.monitorOnly,
            let autoAnswer = Self.defaultQoderAutoAnswer(for: effectiveEvent)
        {
            if effectiveEvent.ingress == .remoteBridge {
                RemoteConnectorManager.shared.respondToIntervention(
                    toolUseId: autoAnswer.toolUseId,
                    decision: "answer",
                    updatedInput: autoAnswer.updatedInput
                )
            } else {
                HookSocketServer.shared.respondToIntervention(
                    toolUseId: autoAnswer.toolUseId,
                    decision: "answer",
                    updatedInput: autoAnswer.updatedInput
                )
            }
            await SessionStore.shared.process(
                .interventionResolved(
                    sessionId: effectiveEvent.sessionId,
                    nextPhase: .processing,
                    submittedAnswers: autoAnswer.answers
                )
            )
        }

        if effectiveEvent.event == "PostToolUse",
            let toolUseId = effectiveEvent.toolUseId,
            let session = await SessionStore.shared.session(for: effectiveEvent.sessionId)
        {
            if session.activePermission?.toolUseId == toolUseId {
                if effectiveEvent.ingress == .remoteBridge {
                    RemoteConnectorManager.shared.respondToPermission(
                        toolUseId: toolUseId,
                        decision: "cancel"
                    )
                } else {
                    HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
                }
                // Tool was approved externally (e.g. terminal) and completed.
                // Resolve the pending Island-side intervention.
                await SessionStore.shared.process(
                    .permissionApproved(sessionId: effectiveEvent.sessionId, toolUseId: toolUseId)
                )
            } else if session.activePermission?.toolUseId != toolUseId {
                if effectiveEvent.ingress == .remoteBridge {
                    RemoteConnectorManager.shared.respondToPermission(
                        toolUseId: toolUseId,
                        decision: "cancel"
                    )
                } else {
                    HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
                }
            }
        }

        let sessionPhase = effectiveEvent.sessionPhase
        if Self.shouldWatchTranscript(for: effectiveEvent, phase: sessionPhase) {
            let session = await SessionStore.shared.session(for: effectiveEvent.sessionId)
            InterruptWatcherManager.shared.startWatching(
                sessionId: effectiveEvent.sessionId,
                transcriptSessionId: effectiveEvent.nativeSessionId,
                cwd: effectiveEvent.cwd,
                explicitFilePath: session?.clientInfo.sessionFilePath
            )
        }

        if Self.shouldStopWatchingTranscript(for: effectiveEvent) {
            InterruptWatcherManager.shared.stopWatching(sessionId: effectiveEvent.sessionId)
        }

        if effectiveEvent.event == "Stop", effectiveEvent.ingress != .remoteBridge {
            HookSocketServer.shared.cancelPendingPermissions(sessionId: effectiveEvent.sessionId)
        }
    }

    /// Project raw hook data to the small, display-only event accepted by Mac Island.
    /// Tool arguments, raw results, credentials, and response controls never cross
    /// this boundary. The retained text is bounded and remains memory-only.
    nonisolated static func productSafeHookEvent(_ event: HookEvent) -> HookEvent {
        let observed = observedEventV1(from: event)
        return HookEvent(
            sessionId: event.sessionId,
            cwd: event.cwd,
            event: event.event,
            status: event.status,
            provider: event.provider,
            clientInfo: event.clientInfo,
            pid: event.pid,
            tty: event.tty,
            tool: event.tool,
            toolInput: nil,
            toolUseId: event.toolUseId,
            notificationType: event.notificationType,
            message: observed?.displayText,
            nativeTitle: observed?.nativeTitle,
            serviceProvider: observed?.provider,
            modelName: observed?.model,
            nativeSessionId: event.nativeSessionId,
            observedAt: observed?.timestamp ?? event.observedAt,
            ingress: event.ingress,
            bridgeIntervention: nil,
            bridgeExpectsResponse: false,
            suppressInAppPrompt: true,
            codexBypassPermissions: event.codexBypassPermissions
        )
    }

    nonisolated static func observedEventV1(from event: HookEvent) -> MacIslandObservedEventV1? {
        let client: MacIslandClientKind
        if event.clientInfo.isDSHClient {
            client = .dsh
        } else if event.clientInfo.isHermesClient {
            client = .hermes
        } else if event.clientInfo.isOpenCodeClient {
            client = .openCode
        } else if event.clientInfo.isClaudeCodeClient {
            client = .claudeCode
        } else {
            return nil
        }

        guard
            let origin = MacIslandSessionOrigin(
                rawValue: event.clientInfo.origin?.lowercased() ?? "cli"
            )
        else {
            return nil
        }

        let textEvents: Set<String> = [
            "UserPromptSubmit",
            "Notification",
            "Stop",
            "StopFailure",
            "TaskCreated",
            "TaskCompleted",
            "SubagentStart",
            "SubagentStop",
        ]
        let displayText =
            textEvents.contains(event.event)
            ? boundedObservedText(event.message, limit: MacIslandPresentationPolicy.conversationDetailCharacterLimit)
            : nil

        return MacIslandObservedEventV1(
            sessionID: event.nativeSessionId ?? event.sessionId,
            client: client,
            origin: origin,
            project: URL(fileURLWithPath: event.cwd).lastPathComponent,
            nativeTitle: boundedObservedText(event.nativeTitle, limit: 180),
            provider: boundedObservedText(event.serviceProvider, limit: 80),
            model: boundedObservedText(event.modelName, limit: 100),
            status: event.status,
            displayText: displayText,
            toolName: boundedObservedText(event.tool, limit: 100),
            timestamp: event.observedAt
        )
    }

    nonisolated private static func boundedObservedText(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let normalized =
            text
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return normalized.count > limit ? String(normalized.prefix(limit)) + "…" : normalized
    }

    /// Await this before explicitly starting monitoring again.
    func stopMonitoring() async {
        monitoringLifecycle.stop()
        HookSocketServer.shared.stop()
        async let codex: Void = CodexReadOnlyClient.shared.stopNotifications()
        async let cursor: Void = CursorConversationMonitor.shared.stop()
        async let liveness: Void = SessionStore.shared.stopLivenessSweep()
        _ = await (codex, cursor, liveness)
    }

    /// Called synchronously from applicationShouldTerminate before yielding to
    /// AppKit, so queued onAppear/start and energy-resume work cannot reopen ingress.
    static func beginApplicationShutdown() {
        SessionMonitoringShutdown.shared.begin()
        PersonalAgentMonitor.shared.shutdown()
    }

    func stopMonitoringForTermination() async {
        Self.beginApplicationShutdown()
        HookSocketServer.shared.stop()
        // Start owned-process cleanup immediately, independently of other actors.
        async let codex: Void = CodexAppServerMonitor.shared.shutdown()
        async let cursor: Void = CursorConversationMonitor.shared.stop()
        async let liveness: Void = SessionStore.shared.stopLivenessSweep()
        async let personalAgents: Void = PersonalAgentMonitor.shared.waitForIdle()
        _ = await (codex, cursor, liveness, personalAgents)
    }

    private func cancelLocalMonitoringWork() {
        if Self.allowsLiveMonitoring() { PersonalAgentMonitor.shared.release(self) }
        energyCancellable?.cancel()
        energyCancellable = nil
        maintenanceTask?.cancel()
        maintenanceTask = nil
        usageRefreshTask?.cancel()
        usageRefreshTask = nil
    }

    private func startEnergyAwareMaintenanceLoop() {
        guard !monitoringLifecycle.isApplicationShuttingDown else { return }
        maintenanceTask?.cancel()
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                let policy = await MainActor.run {
                    EnergyGovernor.shared.policy
                }

                guard let interval = policy.sessionMaintenanceInterval else {
                    try? await Task.sleep(for: .seconds(30))
                    continue
                }

                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }

                await MainActor.run {
                    guard let self else { return }
                    self.refreshVisibleSessions()
                    if MacIslandProductPolicy.usageTrackingEnabled,
                        self.shouldRefreshUsage,
                        AppSettings.showUsage,
                        EnergyGovernor.shared.policy.usageRefreshInterval != nil
                    {
                        self.refreshUsageState()
                    }
                }

                await SessionStore.shared.process(
                    .pruneTimedOutExternalContinuations(now: Date())
                )
                await SessionStore.shared.pruneOrphanedSessions()
            }
        }
    }

    func refreshUsageState() {
        // Opened views request quota refresh separately from startMonitoring.
        // Keep that entrypoint inside the same test / fixture isolation gate.
        guard Self.allowsLiveMonitoring(), !monitoringLifecycle.isApplicationShuttingDown,
            MacIslandProductPolicy.usageTrackingEnabled,
            AppSettings.showUsage
        else {
            usageRefreshTask?.cancel()
            usageRefreshTask = nil
            return
        }

        usageRefreshTask?.cancel()
        usageRefreshTask = Task { [weak self] in
            guard let self, !Task.isCancelled, Self.allowsLiveMonitoring() else { return }

            let canReadClaudeUsage = HookInstaller.isManagedClaudeStatusLineConfigured()
            let cachedClaudeSnapshot =
                canReadClaudeUsage
                ? UsageSnapshotCacheStore.loadClaude().flatMap { $0.isFresh() ? $0 : nil }
                : nil
            let cachedCodexSnapshot = UsageSnapshotCacheStore.loadCodex()
            let cachedCursorSnapshot = MacIslandProductPolicy.monitorOnly ? nil : UsageSnapshotCacheStore.loadCursor()

            let claudeSnapshot =
                canReadClaudeUsage
                ? await Task.detached(priority: .utility) {
                    try? ClaudeUsageLoader.load()
                }.value
                : nil

            let codexSnapshot = await Task.detached(priority: .utility) {
                try? CodexUsageLoader.load()
            }.value

            let appServerCodexSnapshot = await CodexAppServerMonitor.shared.readUsageSnapshot()
            let cursorSnapshot = try? await CursorUsageLoader.load()

            guard !Task.isCancelled else { return }

            if let claudeSnapshot {
                UsageSnapshotCacheStore.saveClaude(claudeSnapshot)
            }
            // The app-server exposes the canonical multi-bucket account quota.
            // Transcript parsing remains a fallback only when that read is not
            // available; it may contain a model-specific allowance instead.
            let resolvedCodexSnapshot = appServerCodexSnapshot ?? codexSnapshot
            let productCodexSnapshot = resolvedCodexSnapshot.map { snapshot in
                MacIslandProductPolicy.privacyShieldEnabled
                    ? snapshot.quotaOnlyProjection
                    : snapshot
            }

            if let productCodexSnapshot {
                UsageSnapshotCacheStore.saveCodex(productCodexSnapshot)
                if !MacIslandProductPolicy.monitorOnly {
                    await AgentUsageStore.shared.recordCodexUsageSnapshot(productCodexSnapshot)
                }
            }

            if let cursorSnapshot {
                UsageSnapshotCacheStore.saveCursor(cursorSnapshot)
            }

            self.claudeUsageSnapshot = claudeSnapshot ?? cachedClaudeSnapshot
            self.codexUsageSnapshot = productCodexSnapshot ?? cachedCodexSnapshot
            self.cursorUsageSnapshot = cursorSnapshot ?? cachedCursorSnapshot
            if !MacIslandProductPolicy.monitorOnly {
                self.syncCodexThreadDiscovery(using: self.codexUsageSnapshot)
            }
        }
    }

    var isUsageRefreshScheduled: Bool { usageRefreshTask != nil }

    private func acceptCodexUsageSnapshot(_ snapshot: CodexUsageSnapshot) {
        guard Self.allowsLiveMonitoring() else { return }
        guard MacIslandProductPolicy.usageTrackingEnabled,
            AppSettings.showUsage
        else {
            return
        }
        let productSnapshot =
            MacIslandProductPolicy.privacyShieldEnabled
            ? snapshot.quotaOnlyProjection
            : snapshot
        UsageSnapshotCacheStore.saveCodex(productSnapshot)
        codexUsageSnapshot = productSnapshot
    }

    // MARK: - Native Runtime

    func startNativeSession(provider: SessionProvider, cwd: String, preferredSessionID: String? = nil) {
        guard !MacIslandProductPolicy.monitorOnly else { return }
        Task {
            _ = try? await runtimeCoordinator.startSession(
                provider: provider,
                cwd: cwd,
                preferredSessionID: preferredSessionID,
                metadata: [:]
            )
        }
    }

    func terminateNativeSession(sessionId: String) {
        guard !MacIslandProductPolicy.monitorOnly else { return }
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                session.ingress == .nativeRuntime
            else {
                return
            }

            try? await runtimeCoordinator.terminateSession(
                provider: session.provider,
                sessionID: session.sessionId
            )
        }
    }

    // MARK: - Permission Handling

    func approvePermission(sessionId: String, forSession: Bool = false) {
        guard !MacIslandProductPolicy.monitorOnly else { return }
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId) else {
                return
            }
            let permission = Self.approvalToolUseId(for: session)
            await clearApprovalNotification(
                for: session,
                toolUseId: permission,
                decision: .approve
            )

            if session.ingress == .nativeRuntime {
                try? await runtimeCoordinator.approveSession(
                    provider: session.provider,
                    sessionID: session.sessionId,
                    forSession: forSession
                )
                await TelemetryService.shared.recordAttentionResolved(
                    session,
                    resolution: forSession ? "approve_for_session" : "approve"
                )
                return
            }

            let shouldRespondToHookPermission =
                session.intervention?.metadata["source"] == "codex_hook_permission"
                && session.activePermission != nil

            if session.ingress == .codexAppServer, !shouldRespondToHookPermission {
                let resolvedSessionId = await SessionStore.shared.resolvedCodexSessionId(for: sessionId)
                await CodexAppServerMonitor.shared.approve(threadId: resolvedSessionId, forSession: forSession)
                await TelemetryService.shared.recordAttentionResolved(
                    session,
                    resolution: forSession ? "approve_for_session" : "approve"
                )
                return
            }

            guard let permission else { return }

            if forSession, session.scopedApprovalAction == .autoApprove {
                await SessionStore.shared.process(
                    .permissionAutoApprovalChanged(sessionId: sessionId, isEnabled: true)
                )
                if session.ingress == .remoteBridge {
                    RemoteConnectorManager.shared.respondToPermission(
                        toolUseId: permission,
                        decision: "approveForSession"
                    )
                } else {
                    HookSocketServer.shared.respondToPermission(
                        toolUseId: permission,
                        decision: "approveForSession"
                    )
                }
                await TelemetryService.shared.recordAttentionResolved(session, resolution: "approve_for_session")
                return
            }

            if session.ingress == .remoteBridge {
                RemoteConnectorManager.shared.respondToPermission(
                    toolUseId: permission,
                    decision: "allow"
                )
            } else {
                HookSocketServer.shared.respondToPermission(
                    toolUseId: permission,
                    decision: "allow"
                )
            }

            await TelemetryService.shared.recordAttentionResolved(session, resolution: "approve")
        }
    }

    func denyPermission(sessionId: String, reason: String?) {
        guard !MacIslandProductPolicy.monitorOnly else { return }
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId) else {
                return
            }
            let permission = Self.approvalToolUseId(for: session)
            await clearApprovalNotification(
                for: session,
                toolUseId: permission,
                decision: .deny(reason: reason)
            )

            if session.ingress == .nativeRuntime {
                try? await runtimeCoordinator.denySession(
                    provider: session.provider,
                    sessionID: session.sessionId,
                    reason: reason
                )
                await TelemetryService.shared.recordAttentionResolved(session, resolution: "deny")
                return
            }

            let shouldRespondToHookPermission =
                session.intervention?.metadata["source"] == "codex_hook_permission"
                && session.activePermission != nil

            if session.ingress == .codexAppServer, !shouldRespondToHookPermission {
                let resolvedSessionId = await SessionStore.shared.resolvedCodexSessionId(for: sessionId)
                await CodexAppServerMonitor.shared.deny(threadId: resolvedSessionId)
                await TelemetryService.shared.recordAttentionResolved(session, resolution: "deny")
                return
            }

            guard let permission else { return }

            if session.ingress == .remoteBridge {
                RemoteConnectorManager.shared.respondToPermission(
                    toolUseId: permission,
                    decision: "deny",
                    reason: reason
                )
            } else {
                HookSocketServer.shared.respondToPermission(
                    toolUseId: permission,
                    decision: "deny",
                    reason: reason
                )
            }

            await TelemetryService.shared.recordAttentionResolved(session, resolution: "deny")
        }
    }

    private enum ApprovalDecision {
        case approve
        case deny(reason: String?)
    }

    private nonisolated static func approvalToolUseId(for session: SessionState) -> String? {
        if let toolUseId = session.activePermission?.toolUseId,
            !toolUseId.isEmpty
        {
            return toolUseId
        }

        guard let intervention = session.intervention,
            intervention.kind == .approval
        else {
            return nil
        }

        return [
            intervention.metadata["originalToolUseId"],
            intervention.metadata["toolUseId"],
            intervention.metadata["tool_use_id"],
            intervention.id,
        ].compactMap { candidate -> String? in
            guard let candidate else { return nil }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }.first
    }

    private func clearApprovalNotification(
        for session: SessionState,
        toolUseId: String?,
        decision: ApprovalDecision
    ) async {
        guard session.needsApprovalResponse else { return }

        guard let toolUseId else {
            await SessionStore.shared.resolveCodexIntervention(
                sessionId: session.sessionId,
                nextPhase: .processing
            )
            return
        }

        switch decision {
        case .approve:
            await SessionStore.shared.process(
                .permissionApproved(sessionId: session.sessionId, toolUseId: toolUseId)
            )
        case .deny(let reason):
            await SessionStore.shared.process(
                .permissionDenied(sessionId: session.sessionId, toolUseId: toolUseId, reason: reason)
            )
        }
    }

    func answerIntervention(sessionId: String, answers: [String: [String]]) {
        guard !MacIslandProductPolicy.monitorOnly else { return }
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId) else {
                return
            }

            if session.ingress == .nativeRuntime {
                try? await runtimeCoordinator.answerSession(
                    provider: session.provider,
                    sessionID: session.sessionId,
                    answers: answers
                )
                await TelemetryService.shared.recordAttentionResolved(session, resolution: "answer")
                return
            }

            if session.ingress == .codexAppServer {
                let resolvedSessionId = await SessionStore.shared.resolvedCodexSessionId(for: sessionId)
                if await CodexAppServerMonitor.shared.answer(threadId: resolvedSessionId, answers: answers) {
                    await TelemetryService.shared.recordAttentionResolved(session, resolution: "answer")
                    return
                }
                guard let intervention = session.intervention,
                    Self.shouldSubmitCodexRolloutUserInput(intervention),
                    let callId = Self.codexRolloutUserInputCallId(for: intervention)
                else {
                    return
                }
                do {
                    try await CodexAppServerMonitor.shared.submitRequestUserInputOutput(
                        threadId: resolvedSessionId,
                        callId: callId,
                        answers: answers
                    )
                    await SessionStore.shared.process(
                        .interventionResolved(
                            sessionId: sessionId,
                            nextPhase: .processing,
                            submittedAnswers: answers
                        )
                    )
                    await TelemetryService.shared.recordAttentionResolved(session, resolution: "answer")
                } catch {
                    NSLog("Failed to submit Codex request_user_input answer: \(error.localizedDescription)")
                }
                return
            }

            guard let intervention = session.intervention,
                intervention.kind == .question,
                let updatedInput = updatedHookToolInput(
                    for: intervention,
                    answers: answers,
                    clientInfo: session.clientInfo
                )
            else {
                return
            }

            // 使用正确的 toolUseId：优先使用 metadata 中保存的原始值
            let toolUseId = intervention.metadata["originalToolUseId"] ?? intervention.id
            if session.ingress == .remoteBridge {
                RemoteConnectorManager.shared.respondToIntervention(
                    toolUseId: toolUseId,
                    decision: "answer",
                    updatedInput: updatedInput
                )
            } else {
                HookSocketServer.shared.respondToIntervention(
                    toolUseId: toolUseId,
                    decision: "answer",
                    updatedInput: updatedInput
                )
            }

            await SessionStore.shared.process(
                .interventionResolved(
                    sessionId: sessionId,
                    nextPhase: .processing,
                    submittedAnswers: answers
                )
            )
            await TelemetryService.shared.recordAttentionResolved(session, resolution: "answer")
            HookWalkthroughDemoRunner.shared.completeIfNeeded(
                sessionId: sessionId,
                intervention: intervention
            )
        }
    }

    func loadCodexThread(sessionId: String) async throws -> CodexThreadSnapshot {
        let session = await SessionStore.shared.session(for: sessionId)
        let resolvedSessionId = await SessionStore.shared.resolvedCodexSessionId(for: sessionId)

        do {
            let snapshot = try await CodexReadOnlyClient.shared.readThread(
                threadId: resolvedSessionId,
                includeTurns: true
            )
            if !snapshot.historyItems.isEmpty || session?.clientInfo.sessionFilePath == nil {
                return snapshot
            }
        } catch {
            if let fallback = await loadCodexRolloutFallback(sessionId: sessionId, session: session) {
                return fallback
            }
            throw error
        }

        if let fallback = await loadCodexRolloutFallback(sessionId: sessionId, session: session) {
            return fallback
        }

        throw NSError(
            domain: "PingIsland.Codex",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "No Codex thread details available yet."]
        )
    }

    func continueCodexThread(sessionId: String, expectedTurnId: String, text: String) async throws {
        guard !MacIslandProductPolicy.monitorOnly else {
            throw MacIslandMonitorOnlyError.controlDisabled
        }
        if let session = await SessionStore.shared.session(for: sessionId),
            session.ingress == .nativeRuntime
        {
            try await runtimeCoordinator.continueSession(
                provider: session.provider,
                sessionID: session.sessionId,
                expectedTurnId: expectedTurnId,
                text: text
            )
            return
        }

        let resolvedSessionId = await SessionStore.shared.resolvedCodexSessionId(for: sessionId)
        try await CodexAppServerMonitor.shared.continueThread(
            threadId: resolvedSessionId,
            expectedTurnId: expectedTurnId,
            text: text
        )
    }

    func sendSessionMessage(sessionId: String, text: String, expectedTurnId: String? = nil) async throws {
        guard !MacIslandProductPolicy.monitorOnly else {
            throw MacIslandMonitorOnlyError.controlDisabled
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let session = await SessionStore.shared.session(for: sessionId) else {
            throw NSError(
                domain: "PingIsland.SessionMonitor",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Session not found."]
            )
        }

        if session.provider == .codex,
            session.ingress == .nativeRuntime
        {
            try await continueCodexThread(
                sessionId: sessionId,
                expectedTurnId: expectedTurnId ?? "",
                text: trimmed
            )
            return
        }

        if session.ingress == .nativeRuntime {
            try await runtimeCoordinator.sendUserInput(
                provider: session.provider,
                sessionID: session.sessionId,
                text: trimmed
            )
            return
        }

        if session.supportsTmuxCLIMessaging {
            guard let target = await findTmuxTarget(for: session) else {
                throw NSError(
                    domain: "PingIsland.SessionMonitor",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "Could not find the terminal pane for this session."]
                )
            }

            guard await ToolApprovalHandler.shared.sendMessage(trimmed, to: target) else {
                throw NSError(
                    domain: "PingIsland.SessionMonitor",
                    code: 500,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Failed to send the follow-up message to the terminal session."
                    ]
                )
            }

            return
        }

        if session.provider == .codex,
            session.ingress == .codexAppServer
        {
            try await continueCodexThread(
                sessionId: sessionId,
                expectedTurnId: expectedTurnId ?? "",
                text: trimmed
            )
            return
        }

        guard session.isInTmux, let tty = session.tty else {
            throw NSError(
                domain: "PingIsland.SessionMonitor",
                code: 400,
                userInfo: [
                    NSLocalizedDescriptionKey: "Inline follow-up requires an active tmux-backed terminal session."
                ]
            )
        }

        guard let target = await findTmuxTarget(tty: tty) else {
            throw NSError(
                domain: "PingIsland.SessionMonitor",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Could not find the terminal pane for this session."]
            )
        }

        guard await ToolApprovalHandler.shared.sendMessage(trimmed, to: target) else {
            throw NSError(
                domain: "PingIsland.SessionMonitor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to send the follow-up message to the terminal session."]
            )
        }
    }

    func sendNativeSessionInput(sessionId: String, text: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                session.ingress == .nativeRuntime
            else {
                return
            }

            try? await runtimeCoordinator.sendUserInput(
                provider: session.provider,
                sessionID: session.sessionId,
                text: text
            )
        }
    }

    /// Archive (remove) a session from the instances list
    func archiveSession(sessionId: String) {
        Task {
            await SessionStore.shared.process(.sessionArchived(sessionId: sessionId))
        }
    }

    // MARK: - State Update

    func observedSession(matching record: RecentSessionRecord) -> SessionState? {
        SessionListPresentation.observedSession(for: record, in: allSessions)
    }

    func hideSessionLocally(_ session: SessionState) {
        localVisibility.hide(session)
        refreshVisibleSessions()
    }

    private func updateFromSessions(_ sessions: [SessionState]) {
        guard sessions != allSessions else { return }
        for session in sessions where session.ingress == .hookBridge || session.ingress == .codexAppServer {
            SessionContinuationService.shared.noteObservedActivity(
                sessionKey: session.sessionId, at: session.lastActivity
            )
        }
        allSessions = sessions
        recentSessions.observe(Self.productSupportedSessions(from: sessions))
        refreshVisibleSessions()
    }

    private func refreshVisibleSessions() {
        recentSessions.prune()
        let visibleSessions = filteredVisibleSessions(from: localVisibility.filter(allSessions))
        let pendingSessions = visibleSessions.filter { $0.needsAttention }
        recordNewAttentionRequests(in: pendingSessions)
        if visibleSessions != instances {
            instances = visibleSessions
        }
        if pendingSessions != pendingInstances {
            pendingInstances = pendingSessions
        }
        let nextSnapshots = MacIslandSessionSnapshot.sorted(
            visibleSessions.compactMap { MacIslandSessionSnapshot.make(from: $0) }
        )
        if nextSnapshots != sessionSnapshots {
            sessionSnapshots = nextSnapshots
        }
    }

    private func recordNewAttentionRequests(in pendingSessions: [SessionState]) {
        let currentIDs = Set(pendingSessions.map(\.sessionId))
        let newSessions = pendingSessions.filter { !telemetryPendingAttentionSessionIDs.contains($0.sessionId) }
        telemetryPendingAttentionSessionIDs = currentIDs

        for session in newSessions {
            Task {
                await TelemetryService.shared.recordAttentionRequested(session)
            }
        }
    }

    private func filteredVisibleSessions(from sessions: [SessionState]) -> [SessionState] {
        let visibilityMode = AppSettings.subagentVisibilityMode
        let primaryVisibleSessions = Self.productSupportedSessions(from: sessions).filter {
            !$0.shouldHideFromPrimaryUI
                && $0.shouldDisplaySubagent(in: visibilityMode)
        }
        let dedupedSessions = Self.deduplicateSameProjectClaudeSessions(from: primaryVisibleSessions)
        return dedupedSessions.filter { candidate in
            guard shouldCheckDuplicateVisibility(for: candidate) else {
                return true
            }

            return !dedupedSessions.contains { other in
                candidate.shouldHideAsDuplicateCodexPlaceholder(comparedTo: other)
                    || candidate.shouldHideAsDuplicateOpenCodeChildSession(comparedTo: other)
            }
        }
    }

    nonisolated static func productSupportedSessions(from sessions: [SessionState]) -> [SessionState] {
        sessions.filter {
            MacIslandProductPolicy.supportsSession(
                provider: $0.provider,
                clientInfo: $0.clientInfo
            )
        }
    }

    /// When Claude is resumed or restarted, concurrent hook events can create multiple
    /// sessions for the same project before endOrphanedSessions has a chance to clean up.
    /// Keep only the most recently active session per provider + cwd pair.
    nonisolated static func deduplicateSameProjectClaudeSessions(
        from sessions: [SessionState]
    ) -> [SessionState] {
        var bestByKey: [String: SessionState] = [:]
        var order: [String] = []

        for session in sessions {
            guard session.provider == .claude else { continue }
            // Cursor can have several distinct composer threads in the same
            // workspace. They must not be collapsed by the legacy Claude
            // process-session de-duplication rule.
            if MacIslandProductPolicy.supportsSession(
                provider: session.provider,
                clientInfo: session.clientInfo
            ) {
                continue
            }
            let cwd = session.cwd
            guard !cwd.isEmpty else { continue }
            let key = "\(session.provider.rawValue):\(cwd)"
            if let existing = bestByKey[key] {
                if session.lastActivity > existing.lastActivity {
                    bestByKey[key] = session
                }
            } else {
                bestByKey[key] = session
                order.append(key)
            }
        }

        let keep = Set(bestByKey.values.map(\.sessionId))
        return sessions.filter { session in
            guard session.provider == .claude, !session.cwd.isEmpty else { return true }
            if MacIslandProductPolicy.supportsSession(
                provider: session.provider,
                clientInfo: session.clientInfo
            ) {
                return true
            }
            return keep.contains(session.sessionId)
        }
    }

    private func shouldCheckDuplicateVisibility(for session: SessionState) -> Bool {
        session.isLikelyEmptyCodexPlaceholderForUI
            || session.isLikelyTransientCodexContinuationPlaceholder
            || session.isLikelyOpenCodeChildSessionPlaceholderForUI
    }

    private func findTmuxTarget(tty: String) async -> TmuxTarget? {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            return nil
        }

        do {
            let output = try await ProcessExecutor.shared.run(
                tmuxPath,
                arguments: ["list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_tty}"]
            )

            let lines = output.components(separatedBy: "\n")
            for line in lines {
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 2 else { continue }

                let target = parts[0]
                let paneTTY = parts[1].replacingOccurrences(of: "/dev/", with: "")
                if paneTTY == tty {
                    return TmuxTarget(from: target)
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    private func findTmuxTarget(for session: SessionState) async -> TmuxTarget? {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            return nil
        }

        let normalizedTTY = session.tty?
            .replacingOccurrences(of: "/dev/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPaneID = session.clientInfo.tmuxPaneIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let output = try await ProcessExecutor.shared.run(
                tmuxPath,
                arguments: [
                    "list-panes",
                    "-a",
                    "-F",
                    "#{session_name}:#{window_index}.#{pane_index} #{pane_id} #{pane_tty}",
                ]
            )

            for line in output.components(separatedBy: "\n") {
                let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
                guard parts.count >= 2 else { continue }

                let target = parts[0]
                let paneID = parts[1]
                let paneTTY =
                    parts.count >= 3
                    ? parts[2].replacingOccurrences(of: "/dev/", with: "")
                    : ""

                if normalizedPaneID?.isEmpty == false,
                    paneID == normalizedPaneID,
                    let target = TmuxTarget(from: target)
                {
                    return target
                }

                if normalizedTTY?.isEmpty == false,
                    paneTTY == normalizedTTY,
                    let target = TmuxTarget(from: target)
                {
                    return target
                }
            }
        } catch {
            // Fall back to the older pid/cwd matching path below.
        }

        if let pid = session.pid,
            let target = await TmuxController.shared.findTmuxTarget(forClaudePid: pid)
        {
            return target
        }

        return nil
    }

    // MARK: - History Loading (for UI)

    /// Request history load for a session
    func loadHistory(sessionId: String, cwd: String) {
        Task {
            await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))
        }
    }

    private enum HookAnswerEncodingStrategy {
        case lookupAliases
        case codeBuddyCLI
        case qoderCLI
        case questionText
        case questionIndex
    }

    private nonisolated static func answerEncodingStrategy(for clientInfo: SessionClientInfo?)
        -> HookAnswerEncodingStrategy
    {
        let normalizedClientInfo = clientInfo?.normalizedForClaudeRouting()
        let profileID = normalizedClientInfo?.profileID?.lowercased()
        let bundleIdentifier = normalizedClientInfo?.bundleIdentifier?.lowercased()

        if profileID == "qoder-cli" || profileID == "qoder-cn-cli" {
            return .qoderCLI
        }

        if profileID == "codebuddy-cli" {
            return .codeBuddyCLI
        }

        if profileID == "qoder"
            || profileID == "qoder-cn"
            || profileID == "qoderwork"
            || profileID == "codebuddy"
            || profileID == "workbuddy"
            || bundleIdentifier == "com.qoder.ide"
            || bundleIdentifier == "com.aliyun.lingma.ide"
            || bundleIdentifier == "com.qoder.work"
            || bundleIdentifier == "com.tencent.codebuddy"
            || bundleIdentifier == "com.codebuddy.app"
            || bundleIdentifier == "com.workbuddy.workbuddy"
        {
            return .lookupAliases
        }

        if clientInfo?.isQwenCodeClient == true {
            return .questionIndex
        }

        return .questionText
    }

    nonisolated static func updatedHookToolInput(
        rawJSON: String,
        answers: [String: [String]],
        clientInfo: SessionClientInfo? = nil
    ) -> [String: Any]? {
        guard let data = rawJSON.data(using: .utf8),
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        var updated = payload
        let questions = payload["questions"] as? [[String: Any]] ?? []
        var encodedAnswers: [String: Any] = [:]

        let encodingStrategy = answerEncodingStrategy(for: clientInfo)

        for (index, question) in questions.enumerated() {
            let lookupKeys = [
                question["id"] as? String,
                question["question"] as? String,
                "\(index)",
            ].compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            guard let values = lookupKeys.compactMap({ answers[$0] }).first, !values.isEmpty else { continue }
            let encodedValue: Any = values.count == 1 ? values[0] : values
            switch encodingStrategy {
            case .lookupAliases:
                for key in lookupKeys {
                    encodedAnswers[key] = encodedValue
                }
            case .codeBuddyCLI:
                for key in lookupKeys + ["q_\(index)"] {
                    encodedAnswers[key] = encodedValue
                }
            case .qoderCLI:
                let outputKeys = [
                    question["question"] as? String,
                    question["header"] as? String,
                    question["id"] as? String,
                ].compactMap { value -> String? in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                for key in outputKeys {
                    encodedAnswers[key] = encodedValue
                }
                if outputKeys.isEmpty {
                    encodedAnswers["\(index)"] = encodedValue
                }
            case .questionIndex:
                encodedAnswers["\(index)"] = encodedValue
            case .questionText:
                let outputKey =
                    (question["question"] as? String)
                    ?? (question["prompt"] as? String)
                    ?? (question["id"] as? String)
                    ?? "\(index)"
                guard !outputKey.isEmpty else { continue }
                encodedAnswers[outputKey] = encodedValue
            }
        }

        updated["answers"] = encodedAnswers
        return updated
    }

    private func updatedHookToolInput(
        for intervention: SessionIntervention,
        answers: [String: [String]],
        clientInfo: SessionClientInfo
    ) -> [String: Any]? {
        guard let rawJSON = intervention.metadata["toolInputJSON"] else {
            return nil
        }

        var updatedInput = Self.updatedHookToolInput(rawJSON: rawJSON, answers: answers, clientInfo: clientInfo)
        if let transcriptCallId = intervention.metadata["transcriptCallId"], !transcriptCallId.isEmpty {
            updatedInput?["tool_call_id"] = transcriptCallId
            updatedInput?["call_id"] = transcriptCallId
        }
        return updatedInput
    }

    nonisolated static func defaultAnswers(for intervention: SessionIntervention) -> [String: [String]] {
        intervention.questions.reduce(into: [String: [String]]()) { partial, question in
            guard let firstOption = question.options.first?.title, !firstOption.isEmpty else { return }
            partial[question.id] = [firstOption]
        }
    }

    nonisolated static func shouldSubmitCodexRolloutUserInput(_ intervention: SessionIntervention) -> Bool {
        intervention.kind == .question
            && intervention.metadata["source"] == "codex_rollout_request_user_input"
            && intervention.metadata["responseMode"] == "external_only"
    }

    nonisolated static func codexRolloutUserInputCallId(for intervention: SessionIntervention) -> String? {
        [
            intervention.metadata["toolUseId"],
            intervention.metadata["callId"],
            intervention.metadata["call_id"],
            intervention.id,
        ]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .first
    }

    nonisolated static func defaultQoderAutoAnswer(
        for event: HookEvent
    ) -> (toolUseId: String, answers: [String: [String]], updatedInput: [String: Any])? {
        let normalizedClientInfo = event.clientInfo.normalizedForClaudeRouting()
        let isManagedQuestion =
            normalizedClientInfo.profileID == "qoder"
            || normalizedClientInfo.profileID == "qoder-cn"
            || normalizedClientInfo.profileID == "qoderwork"
            || normalizedClientInfo.profileID == "codebuddy"
            || normalizedClientInfo.profileID == "codebuddy-cli"
            || normalizedClientInfo.profileID == "workbuddy"
            || normalizedClientInfo.bundleIdentifier == "com.qoder.ide"
            || normalizedClientInfo.bundleIdentifier == "com.aliyun.lingma.ide"
            || normalizedClientInfo.bundleIdentifier == "com.qoder.work"
            || normalizedClientInfo.bundleIdentifier == "com.tencent.codebuddy"
            || normalizedClientInfo.bundleIdentifier == "com.codebuddy.app"
            || normalizedClientInfo.bundleIdentifier == "com.workbuddy.workbuddy"

        guard isManagedQuestion,
            let toolUseId = event.toolUseId,
            let intervention = event.intervention,
            intervention.kind == .question,
            let rawJSON = intervention.metadata["toolInputJSON"]
        else {
            return nil
        }

        let resolvedQuestions = intervention.resolvedQuestions
        guard !resolvedQuestions.isEmpty else {
            return nil
        }

        let answers = defaultAnswers(for: intervention)
        guard answers.count == resolvedQuestions.count,
            let updatedInput = updatedHookToolInput(
                rawJSON: rawJSON,
                answers: answers,
                clientInfo: event.clientInfo
            )
        else {
            return nil
        }

        return (toolUseId, answers, updatedInput)
    }

    private nonisolated static func shouldAutoApproveClaudePermission(for event: HookEvent) async -> Bool {
        guard event.provider == .claude,
            event.event == "PermissionRequest",
            event.status == "waiting_for_approval"
        else {
            return false
        }

        guard let session = await SessionStore.shared.session(for: event.sessionId) else {
            return false
        }

        return session.autoApprovePermissions
            && session.provider == .claude
            && (session.clientInfo.kind == .claudeCode || session.clientInfo.isQwenCodeClient)
    }

    private nonisolated static func resolvePendingApprovalToolUseId(
        for sessionId: String,
        fallback: String?
    ) async -> String? {
        if let toolUseId = await SessionStore.shared.session(for: sessionId)?.activePermission?.toolUseId,
            !toolUseId.isEmpty
        {
            return toolUseId
        }

        guard let fallback, !fallback.isEmpty else { return nil }
        return fallback
    }

    private func loadCodexRolloutFallback(
        sessionId: String,
        session: SessionState?
    ) async -> CodexThreadSnapshot? {
        guard let session else { return nil }

        let snapshot = await CodexRolloutParser.shared.parseThread(
            threadId: sessionId,
            fallbackCwd: session.cwd,
            clientInfo: session.clientInfo
        )

        if let snapshot {
            await SessionStore.shared.syncCodexThreadSnapshot(snapshot, ingress: .hookBridge)
        }

        return snapshot
    }

    private func syncCodexThreadDiscovery(using snapshot: CodexUsageSnapshot?) {
        guard let threadID = snapshot?.threadID else { return }

        Task {
            let alreadyTracked = await SessionStore.shared.containsSession(threadID)
            guard !alreadyTracked else { return }
            await CodexReadOnlyClient.shared.refreshThreadDiscovery(threadId: threadID)
        }
    }

    nonisolated static func shouldWatchTranscript(for event: HookEvent, phase: SessionPhase) -> Bool {
        guard event.ingress != .remoteBridge else { return false }
        switch event.provider {
        case .claude:
            guard event.clientInfo.isClaudeCodeClient else { return false }
            return phase == .processing
        case .codex:
            guard event.ingress == .hookBridge else { return false }
            switch event.event {
            case "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse":
                return event.status != "ended"
            default:
                return phase == .processing || phase == .waitingForInput || phase.isWaitingForApproval
            }
        default:
            return false
        }
    }

    nonisolated static func shouldStopWatchingTranscript(for event: HookEvent) -> Bool {
        guard event.ingress != .remoteBridge else { return true }
        switch event.provider {
        case .claude:
            return event.status == "ended"
        case .codex:
            return event.status == "ended" || event.event == "Stop"
        case .gemini:
            return event.status == "ended"
        default:
            return false
        }
    }
}

// MARK: - Interrupt Watcher Delegate

extension SessionMonitor: JSONLInterruptWatcherDelegate {
    nonisolated func didDetectInterrupt(sessionId: String) {
        Task {
            await SessionStore.shared.process(.interruptDetected(sessionId: sessionId))
        }

        Task { @MainActor in
            InterruptWatcherManager.shared.stopWatching(sessionId: sessionId)
        }
    }

    nonisolated func didObserveFileChange(sessionId: String) {
        Task {
            await SessionStore.shared.requestFileSync(for: sessionId)
        }
    }
}
