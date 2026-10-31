import XCTest

@testable import Ping_Island

final class MacIslandSessionSnapshotTests: XCTestCase {
    func testMapsCodexSessionToMinimalSnapshotWithoutConversationPayload() throws {
        let now = Date()
        let session = SessionState(
            sessionId: "codex-thread",
            cwd: "/tmp/project",
            provider: .codex,
            clientInfo: .codexApp(threadId: "codex-thread"),
            ingress: .codexAppServer,
            phase: .processing,
            lastActivity: now
        )

        let snapshot = try XCTUnwrap(MacIslandSessionSnapshot.make(from: session, now: now))
        XCTAssertEqual(snapshot.client, .codexDesktop)
        XCTAssertEqual(snapshot.status, .working)
        XCTAssertEqual(snapshot.source, .codexAppServer)
        XCTAssertEqual(snapshot.health, .healthy)
        XCTAssertEqual(snapshot.workspace, "/tmp/project")
        XCTAssertEqual(snapshot.jumpTarget.launchURL, "codex://threads/codex-thread")
        XCTAssertEqual(snapshot.title, "Codex")
        XCTAssertFalse(snapshot.title.contains("project"))
    }

    func testPrivacyShieldNeverProjectsPromptDerivedTitle() throws {
        let session = SessionState(
            sessionId: "private-thread",
            cwd: "/tmp/private-workspace",
            projectName: "private-workspace",
            provider: .codex,
            clientInfo: .codexApp(threadId: "private-thread"),
            sessionName: "SECRET_PROMPT_SHOULD_NOT_APPEAR",
            previewText: "PRIVATE_OUTPUT_SHOULD_NOT_APPEAR",
            phase: .processing
        )

        let snapshot = try XCTUnwrap(MacIslandSessionSnapshot.make(from: session))
        XCTAssertEqual(snapshot.title, "Codex")
        let encoded = try JSONEncoder().encode(snapshot)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.contains("SECRET_PROMPT_SHOULD_NOT_APPEAR"))
        XCTAssertFalse(text.contains("PRIVATE_OUTPUT_SHOULD_NOT_APPEAR"))
    }

    func testStaleStateAndAttentionFirstOrdering() throws {
        let now = Date()
        let stale = try XCTUnwrap(
            MacIslandSessionSnapshot.make(
                from: SessionState(
                    sessionId: "stale",
                    cwd: "/tmp/stale",
                    provider: .codex,
                    clientInfo: .codexCLI(),
                    phase: .processing,
                    lastActivity: now.addingTimeInterval(-301)
                ),
                now: now
            ))
        let attention = try XCTUnwrap(
            MacIslandSessionSnapshot.make(
                from: SessionState(
                    sessionId: "attention",
                    cwd: "/tmp/attention",
                    provider: .codex,
                    clientInfo: .codexCLI(),
                    phase: .waitingForInput,
                    lastActivity: now
                ),
                now: now
            ))

        XCTAssertEqual(stale.status, .stale)
        XCTAssertEqual(stale.health, .stale)
        XCTAssertEqual(MacIslandSessionSnapshot.sorted([stale, attention]).map(\.id), ["attention", "stale"])
    }

    func testUnsupportedClientHasNoProductSnapshot() {
        let session = SessionState(
            sessionId: "unsupported",
            cwd: "/tmp/project",
            provider: .gemini,
            clientInfo: SessionClientInfo(
                kind: .custom,
                profileID: "unsupported-agent",
                name: "Unsupported Agent"
            ),
            phase: .processing
        )

        XCTAssertNil(MacIslandSessionSnapshot.make(from: session))
    }

    func testClaudeCodeHasProductSnapshot() throws {
        let session = SessionState(
            sessionId: "claude",
            cwd: "/tmp/project",
            provider: .claude,
            clientInfo: SessionClientInfo(
                kind: .claudeCode,
                profileID: "claude-code",
                name: "Claude Code",
                origin: "cli"
            ),
            phase: .processing
        )

        let snapshot = try XCTUnwrap(MacIslandSessionSnapshot.make(from: session))
        XCTAssertEqual(snapshot.client, .claudeCode)
        XCTAssertEqual(snapshot.status, .working)
    }

    func testCursorJumpTargetKeepsWorkspaceAndApplicationFallback() throws {
        let session = SessionState(
            sessionId: "cursor-session",
            cwd: "/tmp/cursor-workspace",
            provider: .claude,
            clientInfo: SessionClientInfo(
                kind: .custom,
                profileID: "cursor-hooks",
                name: "Cursor",
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                origin: "ide"
            ),
            phase: .processing
        )

        let snapshot = try XCTUnwrap(MacIslandSessionSnapshot.make(from: session))
        XCTAssertEqual(snapshot.client, .cursor)
        XCTAssertEqual(snapshot.jumpTarget.workspace, "/tmp/cursor-workspace")
        XCTAssertEqual(snapshot.jumpTarget.bundleIdentifier, "com.todesktop.230313mzl4w4u92")
        XCTAssertNil(snapshot.jumpTarget.launchURL)
    }
}
