import Darwin
import Foundation
import XCTest

@testable import Ping_Island

/// Tests for the periodic liveness sweep introduced by
/// `fix-claude-sound-triggers`. The sweep removes sessions whose tracked pid
/// is no longer alive (Ctrl-C, OOM, terminal closed) and garbage-collects
/// sessions already in `.ended` phase.
final class SessionStoreLivenessSweepTests: XCTestCase {

    func testPassiveObservedSessionStartWaitsForMeaningfulActivity() async {
        let clients = [
            SessionClientInfo(
                kind: .claudeCode,
                profileID: "claude_code",
                name: "Claude Code",
                bundleIdentifier: "com.anthropic.claudecode"
            ),
            SessionClientInfo(kind: .custom, profileID: "opencode", name: "OpenCode"),
            SessionClientInfo(kind: .custom, profileID: "hermes", name: "Hermes"),
            SessionClientInfo(kind: .custom, profileID: "dsh", name: "DSH"),
        ]
        let store = SessionStore.shared

        for clientInfo in clients {
            let sessionId = "passive-start-\(clientInfo.profileID ?? "unknown")-\(UUID().uuidString)"

            await store.process(
                .hookReceived(
                    makeClaudeEvent(
                        sessionId: sessionId,
                        pid: Int(getpid()),
                        event: "SessionStart",
                        status: "processing",
                        clientInfo: clientInfo
                    )))

            let afterStart = await store.session(for: sessionId)
            XCTAssertNil(
                afterStart,
                "A lifecycle-only \(clientInfo.name ?? "observed client") start must stay out of the UI"
            )

            await store.process(
                .hookReceived(
                    makeClaudeEvent(
                        sessionId: sessionId,
                        pid: Int(getpid()),
                        event: "UserPromptSubmit",
                        status: "processing",
                        clientInfo: clientInfo
                    )))

            let afterPrompt = await store.session(for: sessionId)
            XCTAssertNotNil(
                afterPrompt,
                "Meaningful \(clientInfo.name ?? "observed client") activity must create the session immediately"
            )

            await store.process(.sessionArchived(sessionId: sessionId))
        }
    }

    func testSweepRemovesSessionWithDeadPid() async throws {
        // Spawn /usr/bin/true and wait for it to exit so we have a real pid
        // that is guaranteed dead at the moment we register the session.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        let deadPid = Int(process.processIdentifier)
        XCTAssertGreaterThan(deadPid, 0)
        XCTAssertTrue(
            Darwin.kill(pid_t(deadPid), 0) != 0 && errno == ESRCH,
            "Test setup precondition: spawned pid must be dead before the sweep runs"
        )

        let sessionId = "liveness-dead-\(UUID().uuidString)"
        let store = SessionStore.shared

        await store.process(
            .hookReceived(
                makeClaudeEvent(
                    sessionId: sessionId,
                    pid: deadPid
                )))

        let beforeSweep = await store.session(for: sessionId)
        XCTAssertNotNil(beforeSweep, "Session must exist before sweep")

        await store.sweepDeadOrEndedSessions()

        let afterSweep = await store.session(for: sessionId)
        XCTAssertNil(afterSweep, "Session with dead pid must be removed by the sweep")
    }

    func testSweepRemovesEndedSession() async {
        let sessionId = "liveness-ended-\(UUID().uuidString)"
        let store = SessionStore.shared

        // Use a real SessionEnd hook to drive the session into `.ended` phase
        // (the only public way to invoke markSessionEnded).
        await store.process(
            .hookReceived(
                makeClaudeEvent(
                    sessionId: sessionId,
                    pid: Int(getpid()),
                    event: "UserPromptSubmit",
                    status: "processing"
                )))
        await store.process(
            .hookReceived(
                makeClaudeEvent(
                    sessionId: sessionId,
                    pid: Int(getpid()),
                    event: "SessionEnd",
                    status: "ended"
                )))

        let beforeSweep = await store.session(for: sessionId)
        XCTAssertEqual(
            beforeSweep?.phase, .ended,
            "Test setup precondition: session must reach .ended phase")

        await store.sweepDeadOrEndedSessions()

        let afterSweep = await store.session(for: sessionId)
        XCTAssertNil(afterSweep, ".ended sessions must be garbage-collected by the sweep")
    }

    func testSweepLeavesSessionWithoutPidAlone() async {
        let sessionId = "liveness-nopid-\(UUID().uuidString)"
        let store = SessionStore.shared

        // pid: nil means we cannot assert the process is dead.
        await store.process(
            .hookReceived(
                makeClaudeEvent(
                    sessionId: sessionId,
                    pid: nil
                )))

        await store.sweepDeadOrEndedSessions()

        let afterSweep = await store.session(for: sessionId)
        XCTAssertNotNil(
            afterSweep,
            "Sessions without a tracked pid must NOT be removed on liveness grounds")

        await store.process(.sessionArchived(sessionId: sessionId))
    }

    func testSweepLeavesLiveSessionAlone() async {
        let sessionId = "liveness-live-\(UUID().uuidString)"
        let store = SessionStore.shared

        // getpid() is the test runner itself — guaranteed alive, phase != .ended.
        await store.process(
            .hookReceived(
                makeClaudeEvent(
                    sessionId: sessionId,
                    pid: Int(getpid())
                )))

        await store.sweepDeadOrEndedSessions()

        let afterSweep = await store.session(for: sessionId)
        XCTAssertNotNil(
            afterSweep,
            "Live, non-ended sessions must be untouched by the sweep")

        await store.process(.sessionArchived(sessionId: sessionId))
    }

    // MARK: - Helpers

    private func makeClaudeEvent(
        sessionId: String,
        pid: Int?,
        event: String = "UserPromptSubmit",
        status: String = "processing",
        clientInfo: SessionClientInfo = SessionClientInfo(
            kind: .claudeCode,
            profileID: "claude_code",
            name: "Claude Code",
            bundleIdentifier: "com.anthropic.claudecode"
        )
    ) -> HookEvent {
        HookEvent(
            sessionId: sessionId,
            cwd: "/tmp/project",
            event: event,
            status: status,
            provider: .claude,
            clientInfo: clientInfo,
            pid: pid,
            tty: nil,
            tool: nil,
            toolInput: nil,
            toolUseId: nil,
            notificationType: nil,
            message: nil
        )
    }
}
