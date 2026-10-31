import Foundation
import XCTest

@testable import Ping_Island

final class CodexMonitorHealthTests: XCTestCase {
    func testOnlyOneAttemptStartsWhileConnectingOrConnected() throws {
        var recovery = CodexMonitorRecovery()
        recovery.enable()
        let token = try XCTUnwrap(recovery.begin())
        XCTAssertNil(recovery.begin())
        recovery.connected(token)
        XCTAssertNil(recovery.begin())
        XCTAssertEqual(recovery.health.phase, .connected)
    }

    func testRepeatedFailuresBackOffAndStopAtSixtySeconds() throws {
        var recovery = CodexMonitorRecovery()
        recovery.enable()
        var delays: [TimeInterval] = []
        for _ in 0..<9 {
            let token = try XCTUnwrap(recovery.begin())
            delays.append(try XCTUnwrap(recovery.failed(token, reason: .connectionLost)))
            XCTAssertNil(recovery.failed(token, reason: .connectionLost))
        }
        XCTAssertEqual(delays, [1, 2, 4, 8, 16, 32, 60, 60, 60])
    }

    func testSuccessfulDataReadResetsBackoff() throws {
        var recovery = CodexMonitorRecovery()
        recovery.enable()
        let first = try XCTUnwrap(recovery.begin())
        recovery.failed(first, reason: .initializationFailed)
        let second = try XCTUnwrap(recovery.begin())
        recovery.connected(second)
        recovery.recordRead(second, at: Date())
        XCTAssertEqual(recovery.failed(second, reason: .connectionLost), 1)
    }

    func testCancellationRejectsOldSuccessFailureAndEvents() throws {
        var recovery = CodexMonitorRecovery()
        recovery.enable()
        let token = try XCTUnwrap(recovery.begin())
        recovery.stop()
        recovery.connected(token)
        recovery.recordRead(token, at: Date())
        recovery.recordEvent(token, at: Date())
        XCTAssertNil(recovery.failed(token, reason: .connectionLost))
        XCTAssertEqual(recovery.health, CodexMonitorHealth())
        XCTAssertNil(recovery.begin())
    }

    func testManualInvalidationRejectsPreviousConnectionResults() throws {
        var recovery = CodexMonitorRecovery()
        recovery.enable()
        let old = try XCTUnwrap(recovery.begin())
        recovery.invalidate()
        let current = try XCTUnwrap(recovery.begin())
        recovery.connected(old)
        recovery.recordEvent(old, at: Date())
        XCTAssertFalse(recovery.accepts(old))
        XCTAssertTrue(recovery.accepts(current))
        XCTAssertEqual(recovery.health.phase, .connecting)
        XCTAssertNil(recovery.health.lastEvent)
    }

    func testSleepInvalidatesWorkAndWakeRequiresFreshConnection() throws {
        var recovery = CodexMonitorRecovery()
        recovery.enable()
        let old = try XCTUnwrap(recovery.begin())
        recovery.connected(old)
        recovery.recordRead(old, at: Date(timeIntervalSince1970: 100))
        XCTAssertTrue(recovery.setSuspended(true))
        XCTAssertFalse(recovery.setSuspended(true))
        XCTAssertNil(recovery.begin())
        XCTAssertNil(recovery.failed(old, reason: .connectionLost))
        XCTAssertEqual(recovery.health.phase, .suspended)
        XCTAssertTrue(recovery.setSuspended(false))
        XCTAssertEqual(recovery.health.phase, .stopped)
        let current = try XCTUnwrap(recovery.begin())
        XCTAssertNotEqual(old, current)
        XCTAssertEqual(recovery.health.phase, .connecting)
    }

    func testWakeCannotEnableStoppedMonitor() {
        var recovery = CodexMonitorRecovery()
        _ = recovery.setSuspended(true)
        recovery.stop()
        _ = recovery.setSuspended(false)
        XCTAssertFalse(recovery.enabled)
        XCTAssertNil(recovery.begin())
    }

    func testSuccessfulReadsAndEventsAreSeparateAndSilenceDoesNotDisconnect() throws {
        var recovery = CodexMonitorRecovery()
        recovery.enable()
        let token = try XCTUnwrap(recovery.begin())
        let first = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 100_000)
        recovery.connected(token)
        recovery.recordRead(token, at: first)
        recovery.recordEvent(token, at: first)
        recovery.recordRead(token, at: later)
        XCTAssertEqual(recovery.health.phase, .connected)
        XCTAssertEqual(recovery.health.lastSuccessfulRead, later)
        XCTAssertEqual(recovery.health.lastEvent, first)
        XCTAssertNil(recovery.health.failure)
    }

    func testUnavailableExecutableHasBoundedRetryAndTypedContentFreeReason() throws {
        var recovery = CodexMonitorRecovery()
        recovery.enable()
        let token = try XCTUnwrap(recovery.begin())
        recovery.failed(token, reason: .executableMissing)
        XCTAssertEqual(recovery.health.phase, .unavailable)
        XCTAssertEqual(recovery.health.failure, .executableMissing)
        XCTAssertEqual(recovery.health.retryDelay, 1)
    }

    func testHandshakeAloneDoesNotResetRepeatedReadTimeoutBackoff() throws {
        var recovery = CodexMonitorRecovery()
        recovery.enable()
        var delays: [TimeInterval] = []
        for _ in 0..<4 {
            let token = try XCTUnwrap(recovery.begin())
            recovery.connected(token)
            delays.append(try XCTUnwrap(recovery.failed(token, reason: .requestTimedOut)))
        }
        XCTAssertEqual(delays, [1, 2, 4, 8])
        XCTAssertNil(recovery.health.lastSuccessfulRead)
    }

    @MainActor
    func testBridgeHealthCheckDoesNotCreateMissingLauncherOrDirectory() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let result = HookInstaller.bridgeHealthStatus(supportDirectory: directory)
        XCTAssertFalse(result.isHealthy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor
    func testBridgeHealthCheckDoesNotRepairExistingNonExecutableLauncher() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bin = directory.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let launcher = bin.appendingPathComponent("mac-island-bridge")
        let content = Data("user-owned-invalid-launcher".utf8)
        try content.write(to: launcher)
        let result = HookInstaller.bridgeHealthStatus(supportDirectory: directory)
        XCTAssertFalse(result.isHealthy)
        XCTAssertEqual(try Data(contentsOf: launcher), content)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: bin.path), ["mac-island-bridge"])
    }
}
