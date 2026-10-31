import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class PersonalAgentMonitor: ObservableObject {
    static let shared = PersonalAgentMonitor()

    @Published private(set) var observations: [PersonalAgentObservation] = []
    @Published private(set) var health: [PersonalAgentClient: PersonalAgentHealth] = [:]
    @Published private(set) var enabled: Set<PersonalAgentClient> = []
    @Published private(set) var paused: Set<PersonalAgentClient> = []
    @Published private(set) var navigationFeedback: [PersonalAgentClient: Bool] = [:]

    /// Missing metadata remains a visible source state, never a fake session.
    var unavailableClients: [PersonalAgentClient] {
        Self.unavailableClients(enabled: enabled, observations: observations)
    }

    static func unavailableClients(enabled: Set<PersonalAgentClient>, observations: [PersonalAgentObservation])
        -> [PersonalAgentClient]
    {
        PersonalAgentClient.allCases.filter { client in
            client.canObserve && enabled.contains(client) && !observations.contains { $0.client == client }
        }
    }

    private struct Owner { weak var value: AnyObject? }
    private var owners: [ObjectIdentifier: Owner] = [:]
    private let reader: any PersonalAgentReading
    private let defaults: UserDefaults?
    private let runtimeAllowed: @MainActor () -> Bool
    private let permission: @MainActor () -> Bool
    private let application: @MainActor (PersonalAgentClient) -> PersonalAgentApplication?
    private let automaticallySchedules: Bool
    private var suspended = false
    private var shuttingDown = false
    private var generation: UInt64 = 0
    private var epoch: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    private var retiredTasks: [Task<Void, Never>] = []
    private var pollTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var axObservers: [PersonalAgentClient: AXObserver] = [:]
    private var pendingRefresh = false
    private var lastRefreshRequest: Date = .distantPast
    private var openingApplications: Set<PersonalAgentClient> = []

    init(
        reader: any PersonalAgentReading = PersonalAgentAccessibilityReader(),
        defaults: UserDefaults? = SessionMonitor.allowsLiveMonitoring() ? .standard : nil,
        runtimeAllowed: @escaping @MainActor () -> Bool = { SessionMonitor.allowsLiveMonitoring() },
        permission: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
        application: @escaping @MainActor (PersonalAgentClient) -> PersonalAgentApplication? = PersonalAgentMonitor
            .runningApplication,
        automaticallySchedules: Bool = true
    ) {
        self.reader = reader
        self.defaults = defaults
        self.runtimeAllowed = runtimeAllowed
        self.permission = permission
        self.application = application
        self.automaticallySchedules = automaticallySchedules
        for client in PersonalAgentClient.allCases {
            if client.canObserve, defaults?.bool(forKey: Self.enabledKey(client)) == true { enabled.insert(client) }
            if client.canObserve, defaults?.bool(forKey: Self.pausedKey(client)) == true { paused.insert(client) }
            health[client] = .init(phase: client.canObserve ? .disabled : .sourceUnavailable)
        }
    }

    // No process or AX work is triggered by creating a settings view or fixture.
    // Production's shared instance lives for the app; explicit shutdown owns
    // cancellation and observer removal rather than isolated destruction.
    nonisolated deinit {}

    func acquire(_ owner: AnyObject) {
        guard !shuttingDown, runtimeAllowed() else { return }
        owners[ObjectIdentifier(owner)] = Owner(value: owner)
        if automaticallySchedules, pollTask == nil { startScheduling() }
        if automaticallySchedules { requestRefresh() }
    }

    func release(_ owner: AnyObject) {
        owners.removeValue(forKey: ObjectIdentifier(owner))
        pruneOwners()
        if owners.isEmpty { stopScheduling() }
    }

    func setEnabled(_ value: Bool, for client: PersonalAgentClient) {
        guard client.canObserve, !shuttingDown else { return }
        if value { enabled.insert(client) } else { enabled.remove(client) }
        defaults?.set(value, forKey: Self.enabledKey(client))
        invalidate()
        observations.removeAll { $0.client == client }
        removeObserver(client)
        health[client] = .init(
            phase: value ? (runtimeAllowed() && permission() ? .interfaceUnavailable : .permissionRequired) : .disabled)
        requestRefresh()
    }

    func setPaused(_ value: Bool, for client: PersonalAgentClient) {
        guard client.canObserve, !shuttingDown else { return }
        if value { paused.insert(client) } else { paused.remove(client) }
        defaults?.set(value, forKey: Self.pausedKey(client))
        invalidate()
        observations.removeAll { $0.client == client }
        removeObserver(client)
        health[client] = .init(phase: enabled.contains(client) ? (value ? .paused : .interfaceUnavailable) : .disabled)
        requestRefresh()
    }

    func setSuspended(_ value: Bool) {
        guard suspended != value, !shuttingDown else { return }
        suspended = value
        invalidate()
        observations.removeAll()
        for client in enabled where !paused.contains(client) {
            removeObserver(client)
            health[client] = .init(
                phase: value ? .sleeping : .interfaceUnavailable,
                lastSuccessfulRead: health[client]?.lastSuccessfulRead, version: health[client]?.version)
        }
        if !value { requestRefresh() }
    }

    func requestRefresh() {
        pruneOwners()
        guard automaticallySchedules, !shuttingDown, !suspended, !owners.isEmpty, runtimeAllowed() else { return }
        if refreshTask != nil {
            pendingRefresh = true
            return
        }
        // AX callbacks can be noisy. Coalesce them without a retry storm.
        let delay = max(0, 1 - Date().timeIntervalSince(lastRefreshRequest))
        lastRefreshRequest = Date().addingTimeInterval(delay)
        let currentGeneration = generation
        refreshTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            await self.refresh(generation: currentGeneration)
            guard currentGeneration == self.generation else { return }
            self.refreshTask = nil
            if self.pendingRefresh {
                self.pendingRefresh = false
                self.requestRefresh()
            }
        }
    }

    /// Also used with injected readers in deterministic lifecycle tests.
    func refreshNow() async {
        pruneOwners()
        guard refreshTask == nil, !shuttingDown, !suspended, !owners.isEmpty, runtimeAllowed() else { return }
        await refresh(generation: generation)
    }

    func shutdown() {
        guard !shuttingDown else { return }
        shuttingDown = true
        owners.removeAll()
        stopScheduling()
        observations.removeAll()
    }

    func waitForIdle() async {
        let tasks = retiredTasks
        retiredTasks.removeAll()
        for task in tasks { await task.value }
    }

    func requestAccessibilityPermission() {
        guard runtimeAllowed(), !shuttingDown else { return }
        // This is called only by the explicit permission button, never enable,
        // startup, polling or retry. macOS owns the actual permission decision.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        requestRefresh()
    }

    func openApplication(_ client: PersonalAgentClient) {
        guard runtimeAllowed(), !shuttingDown, !openingApplications.contains(client) else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: client.bundleID) else {
            navigationFeedback[client] = false
            return
        }
        openingApplications.insert(client)
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] app, error in
            let opened = app != nil && error == nil
            guard let self else { return }
            Task { @MainActor in
                self.openingApplications.remove(client)
                guard !self.shuttingDown else { return }
                self.navigationFeedback[client] = opened
            }
        }
    }

    func dismissNavigationFeedback(_ client: PersonalAgentClient) { navigationFeedback.removeValue(forKey: client) }

    private func refresh(generation expected: UInt64) async {
        guard isCurrent(expected) else { return }
        let trusted = !enabled.isEmpty && permission()
        for client in PersonalAgentClient.allCases {
            guard isCurrent(expected) else { return }
            let phase: PersonalAgentHealthPhase?
            if !client.canObserve {
                phase = .sourceUnavailable
            } else if !enabled.contains(client) {
                phase = .disabled
            } else if paused.contains(client) {
                phase = .paused
            } else if !trusted {
                phase = .permissionRequired
            } else {
                phase = nil
            }
            if let phase {
                discard(client, phase: phase)
                continue
            }
            guard let app = application(client) else {
                discard(client, phase: .appNotRunning)
                continue
            }
            guard app.bundleID == client.bundleID, client.supportedVersions.contains(app.version) else {
                discard(client, phase: .unsupportedVersion, version: app.version)
                continue
            }
            if automaticallySchedules { installObserver(app) }
            let result = await reader.read(app)
            guard isCurrent(expected) else { return }
            // Recheck permission and process identity after every asynchronous
            // read: a quit/relaunch or revocation cannot publish old metadata.
            guard permission() else {
                discard(client, phase: .permissionRequired)
                continue
            }
            guard application(client) == app else {
                discard(client, phase: .appNotRunning)
                continue
            }
            switch result.outcome {
            case .permissionRequired: discard(client, phase: .permissionRequired, version: app.version)
            case .failed: discard(client, phase: .readFailed, version: app.version)
            case .budgetExceeded: discard(client, phase: .budgetExceeded, version: app.version)
            case .success:
                epoch &+= 1
                let now = Date()
                let rows = PersonalAgentAdapter.observations(
                    client: client, version: app.version,
                    windows: result.windows, observedAt: now, epoch: epoch)
                observations.removeAll { $0.client == client }
                observations.append(contentsOf: rows)
                health[client] = .init(
                    phase: rows.isEmpty ? .interfaceUnavailable : .observing,
                    lastSuccessfulRead: now, version: app.version)
            }
        }
    }

    private func isCurrent(_ expected: UInt64) -> Bool {
        !Task.isCancelled && expected == generation && !shuttingDown && !suspended && runtimeAllowed()
            && !owners.isEmpty
    }

    private func discard(_ client: PersonalAgentClient, phase: PersonalAgentHealthPhase, version: String? = nil) {
        observations.removeAll { $0.client == client }
        removeObserver(client)
        health[client] = .init(
            phase: phase, lastSuccessfulRead: health[client]?.lastSuccessfulRead,
            version: version ?? health[client]?.version)
    }

    private func invalidate() {
        generation &+= 1
        pendingRefresh = false
        if let refreshTask {
            refreshTask.cancel()
            retiredTasks.append(refreshTask)
        }
        refreshTask = nil
        // Completed tasks do not retain their metadata; keep a bounded tail for
        // final shutdown. AX reads are bounded and the reader is serialized.
        if retiredTasks.count > 8 { retiredTasks.removeFirst(retiredTasks.count - 8) }
    }

    private func pruneOwners() { owners = owners.filter { $0.value.value != nil } }

    private func startScheduling() {
        EnergyGovernor.shared.$policy
            .map { !$0.allowsFileWatcherRetry }.removeDuplicates()
            .sink { [weak self] in self?.setSuspended($0) }.store(in: &subscriptions)
        for name in [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ] {
            NSWorkspace.shared.notificationCenter.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                        PersonalAgentClient.allCases.contains(where: { $0.bundleID == app.bundleIdentifier })
                    else { return }
                    if name == NSWorkspace.didTerminateApplicationNotification {
                        for client in PersonalAgentClient.allCases where client.bundleID == app.bundleIdentifier {
                            if self?.enabled.contains(client) == true, self?.paused.contains(client) == false {
                                self?.discard(client, phase: .appNotRunning)
                            }
                        }
                        self?.invalidate()
                    }
                    self?.requestRefresh()
                }.store(in: &subscriptions)
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = max(
                    .seconds(30), EnergyGovernor.shared.policy.codexThreadListRefreshInterval ?? .seconds(30))
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.pruneOwners()
                if self.owners.isEmpty {
                    self.stopScheduling()
                    return
                }
                self.requestRefresh()
            }
        }
    }

    private func stopScheduling() {
        invalidate()
        pollTask?.cancel()
        pollTask = nil
        subscriptions.removeAll()
        for client in PersonalAgentClient.allCases { removeObserver(client) }
        observations.removeAll()
    }

    private func installObserver(_ app: PersonalAgentApplication) {
        guard axObservers[app.client] == nil else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, _ in
            Task { @MainActor in PersonalAgentMonitor.shared.requestRefresh() }
        }
        guard AXObserverCreate(app.processID, callback, &observer) == .success, let observer else { return }
        let element = AXUIElementCreateApplication(app.processID)
        AXUIElementSetMessagingTimeout(element, 0.05)
        var subscribed = false
        for notification in [
            kAXFocusedWindowChangedNotification, kAXTitleChangedNotification, kAXValueChangedNotification,
        ] {
            if AXObserverAddNotification(observer, element, notification as CFString, nil) == .success {
                subscribed = true
            }
        }
        guard subscribed else { return }  // bounded polling remains available
        axObservers[app.client] = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func removeObserver(_ client: PersonalAgentClient) {
        guard let observer = axObservers.removeValue(forKey: client) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private static func runningApplication(_ client: PersonalAgentClient) -> PersonalAgentApplication? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: client.bundleID).first,
            !app.isTerminated, let url = app.bundleURL
        else { return nil }
        // Bundle caches its info dictionary across in-place source app updates.
        // Read the small plist afresh so a new version uses its own contract.
        let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        let info = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        return .init(client: client, processID: app.processIdentifier, bundleID: client.bundleID, version: version)
    }

    private static func enabledKey(_ client: PersonalAgentClient) -> String {
        "macIsland.personalAgents.enabled.\(client.rawValue)"
    }
    private static func pausedKey(_ client: PersonalAgentClient) -> String {
        "macIsland.personalAgents.paused.\(client.rawValue)"
    }
}
