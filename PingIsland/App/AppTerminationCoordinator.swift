import AppKit

/// Keep AppKit's run loop alive while asynchronous monitor cleanup finishes.
@MainActor
final class AppTerminationCoordinator {
    private enum State { case idle, waiting, finished }
    private var state = State.idle
    private var cleanupTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private let timeout: Duration

    init(timeout: Duration = .seconds(5)) {
        self.timeout = timeout
    }

    func requestTermination(
        cleanup: @escaping @MainActor () async -> Void,
        reply: @escaping @MainActor () -> Void
    ) -> NSApplication.TerminateReply {
        switch state {
        case .finished: return .terminateNow
        case .waiting: return .terminateLater
        case .idle: break
        }
        state = .waiting
        cleanupTask = Task { [weak self] in
            await cleanup()
            self?.finish(timedOut: false, reply: reply)
        }
        timeoutTask = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.finish(timedOut: true, reply: reply)
        }
        return .terminateLater
    }

    private func finish(timedOut: Bool, reply: @MainActor () -> Void) {
        guard state == .waiting else { return }
        state = .finished
        timeoutTask?.cancel()
        timeoutTask = nil
        cleanupTask?.cancel()
        cleanupTask = nil
        if timedOut {
            NSLog("Mac Island monitor shutdown exceeded its deadline")
        }
        reply()
    }
}
