import Foundation

/// Presentation-only data. Native names never become recent-index metadata.
enum SessionListTitle: Equatable, Sendable {
    case native(String)
    case unavailable

    nonisolated static func fromNativeName(_ name: String?) -> Self {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unavailable
        }
        // A native name is not conversation text: do not strip boilerplate,
        // collapse internal spaces, or substitute a prompt / workspace label.
        return .native(name)
    }

    nonisolated var nativeName: String? {
        if case .native(let name) = self { return name }
        return nil
    }
}

enum SessionListPresentation {
    static func clientName(for session: SessionState) -> String {
        if session.provider == .codex { return session.clientInfo.kind == .codexCLI ? "Codex CLI" : "Codex" }
        return RecentSessionRecord(session: session)?.clientName ?? session.clientDisplayName
    }

    nonisolated static func history(
        records: [RecentSessionRecord], currentSessions: [SessionState]
    ) -> [RecentSessionRecord] {
        let currentIDs = Set(currentSessions.compactMap { RecentSessionRecord(session: $0)?.id })
        return records.filter { !currentIDs.contains($0.id) }
    }

    nonisolated static func observedSession(
        for record: RecentSessionRecord, in sessions: [SessionState]
    ) -> SessionState? {
        sessions.first { RecentSessionRecord(session: $0)?.id == record.id }
    }

    nonisolated static func selectedRecord(
        id: String?, in records: [RecentSessionRecord]
    ) -> RecentSessionRecord? {
        records.first { $0.id == id }
    }

    nonisolated static func movingSelection(
        id: String?, delta: Int, in records: [RecentSessionRecord]
    ) -> String? {
        guard !records.isEmpty else { return nil }
        let current = records.firstIndex { $0.id == id } ?? (delta > 0 ? -1 : records.count)
        return records[min(max(current + delta, 0), records.count - 1)].id
    }
}
