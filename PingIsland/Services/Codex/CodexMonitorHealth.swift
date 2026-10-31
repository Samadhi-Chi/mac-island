import Foundation

/// Content-free lifecycle state. Silence is valid: only a transport/request
/// failure changes connected health into retrying.
nonisolated struct CodexMonitorHealth: Equatable, Sendable {
    enum Phase: String, Sendable { case stopped, connecting, connected, retrying, suspended, unavailable }
    enum Failure: String, Sendable {
        case connectionLost, requestTimedOut, initializationFailed, executableMissing
    }
    var phase: Phase = .stopped
    var lastSuccessfulRead: Date?
    var lastEvent: Date?
    var failure: Failure?
    var retryDelay: TimeInterval?
}

/// Actor-owned policy; generations invalidate all work from a replaced connection.
nonisolated struct CodexMonitorRecovery {
    private(set) var health = CodexMonitorHealth()
    private(set) var generation: UInt64 = 0
    private(set) var enabled = false
    private(set) var suspended = false
    private var failures = 0

    mutating func enable() { enabled = true }

    mutating func begin() -> UInt64? {
        guard enabled, !suspended, health.phase != .connecting, health.phase != .connected else { return nil }
        generation &+= 1
        health.phase = .connecting
        health.retryDelay = nil
        return generation
    }

    func accepts(_ token: UInt64) -> Bool {
        enabled && !suspended && generation == token && (health.phase == .connecting || health.phase == .connected)
    }

    mutating func connected(_ token: UInt64) {
        guard accepts(token) else { return }
        health.phase = .connected
        health.failure = nil
        health.retryDelay = nil
    }

    @discardableResult
    mutating func failed(_ token: UInt64, reason: CodexMonitorHealth.Failure) -> TimeInterval? {
        guard accepts(token) else { return nil }
        failures += 1
        let delay = min(60, pow(2, Double(min(failures - 1, 6))))
        health.phase = reason == .executableMissing ? .unavailable : .retrying
        health.failure = reason
        health.retryDelay = delay
        return delay
    }

    mutating func recordRead(_ token: UInt64, at now: Date) {
        guard accepts(token) else { return }
        health.lastSuccessfulRead = now
        // A handshake alone must not reset repeated discovery/read timeouts.
        failures = 0
    }

    mutating func recordEvent(_ token: UInt64, at now: Date) {
        guard accepts(token) else { return }
        health.lastEvent = now
    }

    mutating func invalidate() {
        generation &+= 1
        health.phase = suspended ? .suspended : .stopped
        health.retryDelay = nil
    }

    mutating func setSuspended(_ value: Bool) -> Bool {
        guard suspended != value else { return false }
        suspended = value
        invalidate()
        return true
    }

    mutating func stop() {
        enabled = false
        failures = 0
        invalidate()
        health.phase = .stopped
    }
}
