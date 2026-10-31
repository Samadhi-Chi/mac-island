import XCTest

@testable import Ping_Island

@MainActor
final class SessionActionControllerTests: XCTestCase {
    func testFeedbackFollowsNativeRecordWhenObservedSessionKeyChanges() throws {
        let controller = SessionActionController(navigator: SuspendedNavigator())
        var info = SessionClientInfo(kind: .custom, profileID: "hermes", name: "Hermes", origin: "desktop")
        let session = SessionState(
            sessionId: "native-feedback", cwd: "/tmp/sample", provider: .claude, clientInfo: info)
        let record = try XCTUnwrap(RecentSessionRecord(session: session))
        controller.report(.failed(.targetNotFound), for: record.navigationSession)
        XCTAssertTrue(try XCTUnwrap(controller.feedback).matches(record))
        XCTAssertTrue(try XCTUnwrap(controller.feedback).matches(session))
        info.origin = "cli"
        let otherOrigin = SessionState(
            sessionId: session.sessionId, cwd: session.cwd, provider: .claude, clientInfo: info)
        XCTAssertFalse(try XCTUnwrap(controller.feedback).matches(otherOrigin))
    }

    func testFailureRetainsTargetContextAndPermitsRetry() async {
        let navigator = SuspendedNavigator()
        let controller = SessionActionController(navigator: navigator)
        let session = fixture("first")
        let first = Task { await controller.perform(session) }
        await navigator.waitUntilStarted("first")
        XCTAssertNil(controller.feedback?.result)
        XCTAssertTrue(controller.activeSessionIDs.contains("first"))
        await navigator.finish("first", result: .failed(.targetNotFound))
        await first.value
        XCTAssertEqual(controller.feedback?.sessionID, "first")
        XCTAssertEqual(controller.feedback?.result, .failed(.targetNotFound))
        XCTAssertTrue(controller.activeSessionIDs.isEmpty)

        let retry = Task { await controller.perform(session) }
        await navigator.waitUntilStarted("first")
        await navigator.finish("first", result: .requestSent(.sessionLink))
        await retry.value
        XCTAssertEqual(controller.feedback?.result, .requestSent(.sessionLink))
    }

    func testDoubleClickAndAlternateButtonDoNotDispatchTwice() async {
        let navigator = SuspendedNavigator()
        let controller = SessionActionController(navigator: navigator)
        let session = fixture("same")
        let first = Task { await controller.perform(session) }
        await navigator.waitUntilStarted("same")
        await controller.perform(session)
        await controller.perform(session, action: .openApplication)
        let count = await navigator.callCount
        XCTAssertEqual(count, 1)
        await navigator.finish("same", result: .applicationOpened)
        await first.value
        XCTAssertEqual(controller.feedback?.result, .applicationOpened)
    }

    func testOlderRequestCannotOverwriteNewerTargetFeedback() async {
        let navigator = SuspendedNavigator()
        let controller = SessionActionController(navigator: navigator)
        let first = Task { await controller.perform(fixture("old")) }
        await navigator.waitUntilStarted("old")
        let second = Task { await controller.perform(fixture("new")) }
        await navigator.waitUntilStarted("new")
        await navigator.finish("new", result: .targetConfirmed)
        await second.value
        await navigator.finish("old", result: .failed(.targetNotFound))
        await first.value
        XCTAssertEqual(controller.feedback?.sessionID, "new")
        XCTAssertEqual(controller.feedback?.result, .targetConfirmed)
        XCTAssertTrue(controller.activeSessionIDs.isEmpty)
    }

    func testDismissDoesNotReappearAfterCompletionOrUnlockDuplicateRequest() async {
        let navigator = SuspendedNavigator()
        let controller = SessionActionController(navigator: navigator)
        let session = fixture("dismissed")
        let request = Task { await controller.perform(session) }
        await navigator.waitUntilStarted("dismissed")
        controller.dismissFeedback()
        await controller.perform(session)
        let count = await navigator.callCount
        XCTAssertEqual(count, 1)
        await navigator.finish("dismissed", result: .requestSent(.terminal))
        await request.value
        XCTAssertNil(controller.feedback)
    }

    func testExplicitActionFeedbackSupersedesOlderNavigation() async {
        let navigator = SuspendedNavigator()
        let controller = SessionActionController(navigator: navigator)
        let session = fixture("old")
        let request = Task { await controller.perform(session) }
        await navigator.waitUntilStarted("old")
        controller.report(.unavailable(.navigationSuppressed), for: fixture("other"))
        await navigator.finish("old", result: .targetConfirmed)
        await request.value
        XCTAssertEqual(controller.feedback?.sessionID, "other")
        XCTAssertEqual(controller.feedback?.result, .unavailable(.navigationSuppressed))
    }

    func testOpenApplicationUsesItsOwnNavigationEntryPoint() async {
        let navigator = SuspendedNavigator()
        let controller = SessionActionController(navigator: navigator)
        let request = Task { await controller.perform(fixture("app"), action: .openApplication) }
        await navigator.waitUntilStarted("app")
        let action = await navigator.lastAction
        XCTAssertEqual(action, .openApplication)
        await navigator.finish("app", result: .applicationOpened)
        await request.value
        XCTAssertEqual(controller.feedback?.result, .applicationOpened)
    }

    func testUnknownOriginNeverDispatchesNavigation() async {
        let navigator = SuspendedNavigator()
        let controller = SessionActionController(navigator: navigator)
        var session = fixture("unresolved")
        session.clientInfo.origin = "unknown"
        await controller.perform(session)
        await controller.perform(session, action: .openApplication)
        let count = await navigator.callCount
        XCTAssertEqual(count, 0)
        XCTAssertEqual(controller.feedback?.result, .unavailable(.navigationSuppressed))
    }

    private func fixture(_ id: String) -> SessionState {
        SessionState(sessionId: id, cwd: "/tmp/island-action-fixture")
    }
}

private actor SuspendedNavigator: SessionNavigating {
    private var pending: [String: CheckedContinuation<SessionNavigationResult, Never>] = [:]
    private var startedWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    private(set) var callCount = 0
    private(set) var lastAction: SessionNavigationAction?

    func navigate(_ session: SessionState) async -> SessionNavigationResult {
        await suspend(session.sessionId, action: .returnToSession)
    }

    func openClientApplication(_ session: SessionState) async -> SessionNavigationResult {
        await suspend(session.sessionId, action: .openApplication)
    }

    func waitUntilStarted(_ id: String) async {
        if pending[id] != nil { return }
        await withCheckedContinuation { startedWaiters[id] = $0 }
    }

    func finish(_ id: String, result: SessionNavigationResult) {
        pending.removeValue(forKey: id)?.resume(returning: result)
    }

    private func suspend(_ id: String, action: SessionNavigationAction) async -> SessionNavigationResult {
        callCount += 1
        lastAction = action
        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            startedWaiters.removeValue(forKey: id)?.resume()
        }
    }
}
