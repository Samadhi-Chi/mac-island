import XCTest

@testable import Ping_Island

@MainActor
final class RecentSessionPresentationTests: XCTestCase {
    func testCodexClientLabelDoesNotExposeTransportOriginator() {
        let info = SessionClientInfo(
            kind: .codexApp, name: "codex_work_desktop", bundleIdentifier: "com.openai.codex",
            origin: "desktop")
        let session = SessionState(sessionId: "native-label", cwd: "/tmp/sample", provider: .codex, clientInfo: info)
        XCTAssertEqual(SessionListPresentation.clientName(for: session), "Codex")
    }

    func testHistoryExcludesCurrentIdentityWithoutDeletingRetainedMetadata() throws {
        var info = SessionClientInfo(kind: .custom, profileID: "hermes", name: "Hermes", origin: "desktop")
        let current = SessionState(
            sessionId: MacIslandProductPolicy.observedSessionKey(nativeSessionID: "same", clientInfo: info),
            cwd: "/tmp/sample", provider: .claude, clientInfo: info)
        let currentRecord = try XCTUnwrap(RecentSessionRecord(session: current))
        info.origin = "cli"
        let differentOrigin = SessionState(
            sessionId: MacIslandProductPolicy.observedSessionKey(nativeSessionID: "same", clientInfo: info),
            cwd: current.cwd, provider: .claude, clientInfo: info)
        let cliRecord = try XCTUnwrap(RecentSessionRecord(session: differentOrigin))
        let other = RecentSessionRecord(
            sessionID: "other", nativeSessionID: "other", client: .codexDesktop,
            origin: "desktop", workspace: current.cwd, lastActivity: current.lastActivity)
        let index = RecentSessionIndex(fileURL: nil)
        index.ingest([currentRecord, cliRecord, other])
        let retained = index.records
        XCTAssertEqual(
            Set(SessionListPresentation.history(records: retained, currentSessions: [current]).map(\.id)),
            Set([cliRecord.id, other.id]))
        XCTAssertEqual(index.records, retained)
        XCTAssertEqual(SessionListPresentation.history(records: retained, currentSessions: []), retained)
        XCTAssertNil(SessionListPresentation.observedSession(for: cliRecord, in: [current]))
    }

    func testKeyboardSelectionUsesOnlyVisibleHistoryAndRejectsStaleSelection() {
        let first = record("first")
        let second = record("second")
        XCTAssertEqual(SessionListPresentation.movingSelection(id: nil, delta: 1, in: [first, second]), first.id)
        XCTAssertEqual(SessionListPresentation.movingSelection(id: first.id, delta: 1, in: [first, second]), second.id)
        XCTAssertEqual(
            SessionListPresentation.movingSelection(id: second.id, delta: -1, in: [first, second]), first.id)
        XCTAssertNil(SessionListPresentation.selectedRecord(id: first.id, in: [second]))
        XCTAssertNil(SessionListPresentation.movingSelection(id: first.id, delta: 1, in: []))
    }

    private func record(_ id: String) -> RecentSessionRecord {
        RecentSessionRecord(
            sessionID: id, nativeSessionID: id, client: .codexDesktop,
            origin: "desktop", workspace: "/tmp/sample", lastActivity: Date())
    }

    func testExplicitFloatingListRemainsReachableWhenCurrentSessionsAreEmpty() {
        XCTAssertTrue(DetachedIslandContentModel.canPresentBubble(from: [], mode: .pinnedList))
        XCTAssertFalse(DetachedIslandContentModel.canPresentBubble(from: [], mode: .hoverPreview))
    }

    func testExplicitRecentSelectionPinsHoverAndRemainsAvailableAfterCurrentWorkEnds() throws {
        let interaction = DetachedIslandInteractionModel()
        interaction.presentHoverPreview(canPresentBubble: true)
        interaction.pinForExplicitContent()
        let mode = try XCTUnwrap(interaction.bubbleContentMode)
        XCTAssertEqual(mode, .pinnedList)
        XCTAssertTrue(DetachedIslandContentModel.canPresentBubble(from: [], mode: mode))
        // Selecting the entry again must not toggle an already pinned list off.
        interaction.pinForExplicitContent()
        XCTAssertEqual(interaction.bubbleState, .pinned)
        interaction.hidePinnedBubble()
        XCTAssertEqual(interaction.bubbleState, .hidden)
    }

    func testRecentRecordRebuildsNativeClientMetadataWithoutOldProcessOrURL() {
        let record = RecentSessionRecord(
            sessionID: "observed:hermes:desktop:old-record", nativeSessionID: "old-record",
            client: .hermes, origin: "desktop", workspace: "/tmp/example", lastActivity: Date()
        )
        let session = record.navigationSession
        XCTAssertNil(session.pid)
        XCTAssertNil(session.tty)
        XCTAssertNil(session.clientInfo.terminalSessionIdentifier)
        XCTAssertNil(session.clientInfo.launchURL)
        XCTAssertEqual(session.clientInfo.bundleIdentifier, "com.nousresearch.hermes.setup")
        XCTAssertEqual(SessionNavigationIdentity.nativeSessionID(for: session), "old-record")
    }
}
