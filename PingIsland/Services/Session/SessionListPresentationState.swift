import Combine

enum SessionListSection: String, CaseIterable, Identifiable {
    case current
    case recent
    var id: String { rawValue }
    var title: String { self == .current ? "当前会话" : "最近记录" }
}

/// Ephemeral selection shared while switching between docked and floating UI.
@MainActor
final class SessionListPresentationState: ObservableObject {
    // This only releases value state; no executor hop is needed on older runtimes.
    nonisolated deinit {}
    static let shared = SessionListPresentationState()
    @Published var section: SessionListSection = .current
}
