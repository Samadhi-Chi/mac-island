import Foundation

/// Narrow Codex app-server capability exposed to Mac Island's active V1 paths.
///
/// This wrapper intentionally has no start/resume/archive/steer, approval, or
/// message APIs. Mutating methods retained in the upstream monitor are also
/// guarded by MacIslandProductPolicy for defense in depth.
actor CodexReadOnlyClient {
    static let shared = CodexReadOnlyClient()

    private let monitor: CodexAppServerMonitor

    init(monitor: CodexAppServerMonitor = .shared) {
        self.monitor = monitor
    }

    func startNotifications() async {
        await monitor.start()
    }

    func stopNotifications() async {
        await monitor.stop()
    }

    func healthSnapshot() async -> CodexMonitorHealth {
        await monitor.healthSnapshot()
    }

    func reconnect() async { await monitor.reconnect() }

    func setSuspended(_ suspended: Bool) async { await monitor.setSuspended(suspended) }

    func readThread(
        threadId: String,
        includeTurns: Bool = true
    ) async throws -> CodexThreadSnapshot {
        try await monitor.readThread(threadId: threadId, includeTurns: includeTurns)
    }

    func refreshThreadDiscovery(threadId: String) async {
        await monitor.refreshThreadDiscovery(threadId: threadId)
    }

    func readThreadName(threadId: String) async throws -> String? {
        try await monitor.readThreadName(threadId: threadId)
    }
}
