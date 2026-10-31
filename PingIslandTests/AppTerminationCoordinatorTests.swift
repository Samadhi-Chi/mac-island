import AppKit
import XCTest

@testable import Ping_Island

@MainActor
final class AppTerminationCoordinatorTests: XCTestCase {
    func testRepeatedQuitWaitsForCleanupAndRepliesExactlyOnce() async {
        let coordinator = AppTerminationCoordinator()
        let latch = TerminationTestLatch()
        let entered = expectation(description: "cleanup entered")
        let replied = expectation(description: "termination reply")
        var cleanups = 0
        var replies = 0
        let cleanup: @MainActor () async -> Void = {
            cleanups += 1
            entered.fulfill()
            await latch.wait()
        }
        let reply: @MainActor () -> Void = {
            replies += 1
            replied.fulfill()
        }
        XCTAssertEqual(coordinator.requestTermination(cleanup: cleanup, reply: reply), .terminateLater)
        XCTAssertEqual(coordinator.requestTermination(cleanup: cleanup, reply: reply), .terminateLater)
        await fulfillment(of: [entered], timeout: 1)
        XCTAssertEqual(cleanups, 1)
        XCTAssertEqual(replies, 0)
        await latch.open()
        await fulfillment(of: [replied], timeout: 1)
        XCTAssertEqual(replies, 1)
        XCTAssertEqual(coordinator.requestTermination(cleanup: cleanup, reply: reply), .terminateNow)
        XCTAssertEqual(cleanups, 1)
    }

    func testTimeoutDoesNotWaitForUncooperativeCleanupOrReplyAgainWhenItFinishes() async {
        let coordinator = AppTerminationCoordinator(timeout: .milliseconds(30))
        let latch = TerminationTestLatch()
        let replied = expectation(description: "bounded termination reply")
        let completed = expectation(description: "late cleanup completed")
        var replies = 0
        let started = ContinuousClock.now
        XCTAssertEqual(
            coordinator.requestTermination(
                cleanup: {
                    await latch.wait()  // Deliberately ignores cancellation.
                    completed.fulfill()
                },
                reply: {
                    replies += 1
                    replied.fulfill()
                }), .terminateLater)
        await fulfillment(of: [replied], timeout: 1)
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
        XCTAssertEqual(replies, 1)
        await latch.open()
        await fulfillment(of: [completed], timeout: 1)
        // Let the completion path reach its once-only guard.
        await Task.yield()
        XCTAssertEqual(replies, 1)
    }

    func testImmediateCleanupCancelsDeadline() async throws {
        let coordinator = AppTerminationCoordinator(timeout: .milliseconds(50))
        let replied = expectation(description: "termination reply")
        var replies = 0
        XCTAssertEqual(
            coordinator.requestTermination(
                cleanup: {},
                reply: {
                    replies += 1
                    replied.fulfill()
                }), .terminateLater)
        await fulfillment(of: [replied], timeout: 1)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(replies, 1)
    }
}

private actor TerminationTestLatch {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
