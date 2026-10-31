import Darwin
import Foundation
import XCTest

@testable import Ping_Island

final class CodexOwnedProcessShutdownTests: XCTestCase {
    func testGracefulStopWaitsForOwnedChildExitAndLeavesOtherChildRunning() async throws {
        let owned = try launchChild(ignoresTermination: false)
        defer { forceCleanup(owned) }
        let unrelated = try launchChild(ignoresTermination: false)
        defer { forceCleanup(unrelated) }

        let result = await CodexOwnedProcessShutdown.stop(owned)

        XCTAssertEqual(result, .exited)
        XCTAssertFalse(owned.isRunning)
        XCTAssertTrue(unrelated.isRunning)
        _ = await CodexOwnedProcessShutdown.stop(unrelated)
    }

    func testTermTimeoutEscalatesOnlyTheOwnedChildAndConfirmsItsExit() async throws {
        let child = try launchChild(ignoresTermination: true)
        defer { forceCleanup(child) }
        let clock = ContinuousClock()
        let started = clock.now

        let result = await CodexOwnedProcessShutdown.stop(child, gracefulTimeout: .milliseconds(50))

        XCTAssertEqual(result, .killed)
        XCTAssertFalse(child.isRunning)
        XCTAssertEqual(child.terminationReason, .uncaughtSignal)
        XCTAssertEqual(child.terminationStatus, SIGKILL)
        XCTAssertLessThan(clock.now - started, .seconds(2))
    }

    func testCancelledCallerStillWaitsForChildCleanup() async throws {
        let child = try launchChild(ignoresTermination: true)
        defer { forceCleanup(child) }
        let stop = Task {
            await CodexOwnedProcessShutdown.stop(child, gracefulTimeout: .milliseconds(50))
        }
        stop.cancel()

        let result = await stop.value

        XCTAssertEqual(result, .killed)
        XCTAssertFalse(child.isRunning)
    }

    func testStoppingAnExitedChildAgainIsHarmless() async throws {
        let child = try launchChild(ignoresTermination: false)
        defer { forceCleanup(child) }
        _ = await CodexOwnedProcessShutdown.stop(child)

        let result = await CodexOwnedProcessShutdown.stop(child)

        XCTAssertEqual(result, .exited)
        XCTAssertFalse(child.isRunning)
    }

    private func launchChild(ignoresTermination: Bool) throws -> Process {
        let child = Process()
        let ready = Pipe()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        // exec keeps the same owned PID; this fixture creates no descendants.
        // Ignored signals survive exec, so readiness also confirms TERM policy.
        child.arguments = ["-c", "\(ignoresTermination ? "trap '' TERM; " : "")printf R; exec /bin/sleep 30"]
        child.standardOutput = ready
        child.standardError = FileHandle.nullDevice
        try child.run()
        XCTAssertEqual(ready.fileHandleForReading.readData(ofLength: 1), Data("R".utf8))
        try? ready.fileHandleForReading.close()
        return child
    }

    private func forceCleanup(_ child: Process) {
        if child.isRunning { _ = kill(child.processIdentifier, SIGKILL) }
    }
}
