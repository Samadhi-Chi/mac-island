import XCTest

@testable import Ping_Island

@MainActor
final class SessionQuickActionsTests: XCTestCase {
    func testHiddenSessionKeepsItsStateAndReappearsOnlyForNewActivity() {
        var state = LocalSessionVisibilityState()
        var session = fixture("hidden", seconds: 10)
        session.previewText = "in-memory context"
        state.hide(session)
        XCTAssertTrue(state.filter([session]).isEmpty)
        session.phase = .idle
        XCTAssertTrue(state.filter([session]).isEmpty)
        session.lastActivity = Date(timeIntervalSince1970: 11)
        let visible = state.filter([session])
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible.first?.previewText, "in-memory context")
    }

    func testHidingParentAlsoHidesItsChildrenWithoutHidingUnrelatedSessions() {
        var state = LocalSessionVisibilityState()
        let parent = fixture("parent", seconds: 10)
        var child = fixture("child", seconds: 10)
        child.codexParentThreadId = "parent"
        let other = fixture("other", seconds: 10)
        state.hide(parent)
        XCTAssertEqual(state.filter([parent, child, other]).map(\.sessionId), ["other"])
    }

    func testRemovedSessionDoesNotLeaveAnUnboundedVisibilityOverride() {
        var state = LocalSessionVisibilityState()
        let session = fixture("gone", seconds: 10)
        state.hide(session)
        XCTAssertTrue(state.filter([]).isEmpty)
        XCTAssertEqual(state.filter([session]).count, 1)
    }

    func testAttentionShortcutCyclesOnlyAttentionSessionsAndHandlesRemoval() {
        var first = fixture("first", seconds: 10)
        first.phase = .waitingForInput
        var second = fixture("second", seconds: 20)
        second.phase = .waitingForInput
        let idle = fixture("idle", seconds: 30)
        let candidates = [idle, first, second]
        let start = SessionShortcutSelection.nextAttention(in: candidates, after: nil)!
        let next = SessionShortcutSelection.nextAttention(in: candidates, after: start.sessionId)!
        XCTAssertNotEqual(next.sessionId, start.sessionId)
        XCTAssertEqual(
            SessionShortcutSelection.nextAttention(in: candidates, after: next.sessionId)?.sessionId, start.sessionId)
        XCTAssertEqual(SessionShortcutSelection.nextAttention(in: [first], after: "removed")?.sessionId, "first")
        XCTAssertNil(SessionShortcutSelection.nextAttention(in: [idle], after: nil))
        XCTAssertTrue(SessionShortcutSelection.preferred(from: candidates)!.needsManualAttention)
    }

    func testCopiedIdentityRemovesOneMatchingNamespaceOnly() {
        let info = SessionClientInfo(kind: .custom, profileID: "hermes", origin: "desktop")
        let native = "observed:inside-native-id"
        let session = SessionState(
            sessionId: MacIslandProductPolicy.observedSessionKey(nativeSessionID: native, clientInfo: info),
            cwd: "/tmp/example", clientInfo: info
        )
        XCTAssertEqual(SessionNavigationIdentity.nativeSessionID(for: session), native)
        XCTAssertEqual(
            SessionNavigationIdentity.nativeSessionID(for: fixture("ordinary-id", seconds: 0)), "ordinary-id")
    }

    private func fixture(_ id: String, seconds: TimeInterval) -> SessionState {
        SessionState(
            sessionId: id, cwd: "/tmp/example", phase: .idle,
            lastActivity: Date(timeIntervalSince1970: seconds), createdAt: Date(timeIntervalSince1970: seconds))
    }
}
