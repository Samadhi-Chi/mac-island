import Foundation

enum SessionLocalAction: Equatable, Sendable {
    case copiedSessionID
    case hiddenLocally
}

enum SessionNavigationIdentity {
    nonisolated static func nativeSessionID(for session: SessionState) -> String {
        let prefix = MacIslandProductPolicy.observedSessionKey(nativeSessionID: "", clientInfo: session.clientInfo)
        return !prefix.isEmpty && session.sessionId.hasPrefix(prefix)
            ? String(session.sessionId.dropFirst(prefix.count)) : session.sessionId
    }
}

/// Hiding is a presentation override. SessionStore remains the lifecycle owner.
struct LocalSessionVisibilityState {
    private var hiddenAtActivity: [String: Date] = [:]

    mutating func hide(_ session: SessionState) {
        hiddenAtActivity[session.sessionId] = session.lastActivity
    }

    mutating func filter(_ sessions: [SessionState]) -> [SessionState] {
        let byID = Dictionary(sessions.map { ($0.sessionId, $0) }, uniquingKeysWith: { _, latest in latest })
        hiddenAtActivity = hiddenAtActivity.filter { id, activity in
            guard let session = byID[id] else { return false }
            return session.lastActivity <= activity
        }
        return sessions.filter { session in
            hiddenAtActivity[session.sessionId] == nil
                && session.linkedParentSessionId.flatMap { hiddenAtActivity[$0] } == nil
                && session.codexParentThreadId.flatMap { hiddenAtActivity[$0] } == nil
        }
    }
}

enum SessionShortcutSelection {
    nonisolated static func preferred(from sessions: [SessionState]) -> SessionState? {
        nextAttention(in: sessions, after: nil)
            ?? IslandExpandedRouteResolver.orderedSessions(from: sessions).first
    }

    nonisolated static func nextAttention(in sessions: [SessionState], after sessionID: String?) -> SessionState? {
        let candidates = IslandExpandedRouteResolver.orderedSessions(from: sessions).filter(\.needsManualAttention)
        guard !candidates.isEmpty else { return nil }
        guard let sessionID, let index = candidates.firstIndex(where: { $0.sessionId == sessionID }) else {
            return candidates.first
        }
        return candidates[(index + 1) % candidates.count]
    }
}
