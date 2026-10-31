import Darwin
import Foundation

/// Only accepts the retained Process that the monitor itself launched. Never
/// discover a process by port/name or signal a process group: a connected
/// external app-server belongs to its client, not to Island.
nonisolated enum CodexOwnedProcessShutdown {
    enum Result: Equatable, Sendable { case exited, killed, timedOut }

    static func stop(
        _ child: Process,
        gracefulTimeout: Duration = .seconds(1),
        forceKillTimeout: Duration = .seconds(1)
    ) async -> Result {
        // Shutdown must finish even if the initiating monitoring task was
        // cancelled. Poll asynchronously so the main actor remains available
        // for AppKit's terminate-later reply and Foundation's exit observation.
        await Task.detached(priority: .userInitiated) {
            guard child.isRunning else { return .exited }
            child.terminate()
            if await waitForExit(child, timeout: gracefulTimeout) { return .exited }
            if child.isRunning {
                // The handle is retained throughout, and only this exact
                // owned child receives the escalation after its grace period.
                _ = kill(child.processIdentifier, SIGKILL)
            }
            return await waitForExit(child, timeout: forceKillTimeout) ? .killed : .timedOut
        }.value
    }

    private static func waitForExit(_ child: Process, timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while child.isRunning, clock.now < deadline {
            try? await Task.sleep(for: min(.milliseconds(10), deadline - clock.now))
        }
        return !child.isRunning
    }
}
