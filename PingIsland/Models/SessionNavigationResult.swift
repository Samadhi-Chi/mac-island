import Foundation

/// Evidence returned by navigation, never evidence that an agent resumed work.
enum SessionNavigationResult: Equatable, Sendable {
    case targetConfirmed
    case requestSent(SessionNavigationTarget)
    case applicationOpened
    case completed(SessionLocalAction)
    case unavailable(SessionNavigationFailure)
    case failed(SessionNavigationFailure)

    nonisolated var wasDispatched: Bool {
        switch self {
        case .targetConfirmed, .requestSent, .applicationOpened, .completed: true
        case .unavailable, .failed: false
        }
    }
}

enum SessionNavigationTarget: Equatable, Sendable {
    case sessionLink
    case terminal
    case workspace
    case tmux
}

enum SessionNavigationFailure: Equatable, Sendable {
    case navigationSuppressed
    case targetNotFound
    case invalidWorkspace
    case clipboardUnavailable
}

enum SessionNavigationAction: Equatable, Sendable {
    case returnToSession
    case openApplication
}

nonisolated protocol SessionNavigating: Sendable {
    func navigate(_ session: SessionState) async -> SessionNavigationResult
    func openClientApplication(_ session: SessionState) async -> SessionNavigationResult
}
