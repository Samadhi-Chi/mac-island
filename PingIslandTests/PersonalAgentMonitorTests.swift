import Foundation
import XCTest

@testable import Ping_Island

@MainActor
final class PersonalAgentMonitorTests: XCTestCase {
    func testDefaultOffAndDotUnavailableNeverReadClients() async {
        let reader = PersonalAgentFakeReader()
        let monitor = makeMonitor(reader)
        let owner = NSObject()
        monitor.acquire(owner)
        await monitor.refreshNow()
        XCTAssertTrue(monitor.enabled.isEmpty)
        XCTAssertEqual(monitor.health[.dot]?.phase, .sourceUnavailable)
        let calls = await reader.calls
        XCTAssertTrue(calls.isEmpty)
        monitor.setEnabled(true, for: .dot)
        XCTAssertFalse(monitor.enabled.contains(.dot))
        monitor.shutdown()
    }

    func testEnablePauseResumeAndFinalOwnerReleaseClearOnlyIslandObservation() async {
        let reader = PersonalAgentFakeReader()
        let monitor = makeMonitor(reader)
        let first = NSObject()
        let second = NSObject()
        monitor.acquire(first)
        monitor.acquire(second)
        monitor.setEnabled(true, for: .muse)
        await monitor.refreshNow()
        XCTAssertEqual(monitor.observations.count, 1)
        monitor.release(first)
        XCTAssertEqual(monitor.observations.count, 1)
        monitor.setPaused(true, for: .muse)
        XCTAssertTrue(monitor.observations.isEmpty)
        await monitor.refreshNow()
        XCTAssertEqual(monitor.health[.muse]?.phase, .paused)
        monitor.setPaused(false, for: .muse)
        await monitor.refreshNow()
        XCTAssertEqual(monitor.observations.count, 1)
        monitor.release(second)
        XCTAssertTrue(monitor.observations.isEmpty)
        monitor.shutdown()
    }

    func testPermissionMissingAndRevokedDuringReadCannotPublishPrivateMetadata() async {
        let reader = PersonalAgentFakeReader()
        let trusted = PersonalAgentTestValue(false)
        let monitor = makeMonitor(reader, permission: { trusted.value })
        let owner = NSObject()
        monitor.acquire(owner)
        monitor.setEnabled(true, for: .muse)
        await monitor.refreshNow()
        XCTAssertEqual(monitor.health[.muse]?.phase, .permissionRequired)
        let initialCalls = await reader.calls
        XCTAssertTrue(initialCalls.isEmpty)
        trusted.value = true
        let gate = PersonalAgentTestGate()
        await reader.setGate(gate)
        let read = Task { await monitor.refreshNow() }
        await gate.waitUntilEntered()
        trusted.value = false
        await gate.open()
        await read.value
        XCTAssertTrue(monitor.observations.isEmpty)
        XCTAssertEqual(monitor.health[.muse]?.phase, .permissionRequired)
        monitor.shutdown()
    }

    func testDelayedReadCannotUndoDisablePauseOrSleep() async {
        for change in ["disable", "pause", "sleep"] {
            let reader = PersonalAgentFakeReader()
            let gate = PersonalAgentTestGate()
            await reader.setGate(gate)
            let monitor = makeMonitor(reader)
            let owner = NSObject()
            monitor.acquire(owner)
            monitor.setEnabled(true, for: .muse)
            let read = Task { await monitor.refreshNow() }
            await gate.waitUntilEntered()
            switch change {
            case "disable": monitor.setEnabled(false, for: .muse)
            case "pause": monitor.setPaused(true, for: .muse)
            default: monitor.setSuspended(true)
            }
            await gate.open()
            await read.value
            XCTAssertTrue(monitor.observations.isEmpty, change)
            XCTAssertEqual(
                monitor.health[.muse]?.phase, change == "disable" ? .disabled : change == "pause" ? .paused : .sleeping)
            monitor.shutdown()
        }
    }

    func testQuitOrProcessReplacementDuringReadCannotPublishOldWindow() async {
        let reader = PersonalAgentFakeReader()
        let gate = PersonalAgentTestGate()
        await reader.setGate(gate)
        let app = PersonalAgentTestValue<PersonalAgentApplication?>(Self.application(.muse))
        let monitor = makeMonitor(reader, application: { _ in app.value })
        let owner = NSObject()
        monitor.acquire(owner)
        monitor.setEnabled(true, for: .muse)
        let read = Task { await monitor.refreshNow() }
        await gate.waitUntilEntered()
        app.value = .init(
            client: .muse, processID: 999_998, bundleID: PersonalAgentClient.muse.bundleID, version: "4.1")
        await gate.open()
        await read.value
        XCTAssertTrue(monitor.observations.isEmpty)
        XCTAssertEqual(monitor.health[.muse]?.phase, .appNotRunning)
        app.value = nil
        await monitor.refreshNow()
        XCTAssertTrue(monitor.observations.isEmpty)
        monitor.shutdown()
    }

    func testUnverifiedVersionOrWrongBundleNeverCallsReader() async {
        for bundle in [PersonalAgentClient.muse.bundleID, "example.unapproved"] {
            let reader = PersonalAgentFakeReader()
            let monitor = makeMonitor(
                reader,
                application: { _ in
                    .init(client: .muse, processID: 999_999, bundleID: bundle, version: "99.0")
                })
            let owner = NSObject()
            monitor.acquire(owner)
            monitor.setEnabled(true, for: .muse)
            await monitor.refreshNow()
            XCTAssertEqual(monitor.health[.muse]?.phase, .unsupportedVersion)
            let calls = await reader.calls
            XCTAssertTrue(calls.isEmpty)
            monitor.shutdown()
        }
    }

    func testReadFailureOrBudgetExhaustionDoesNotBlockOtherClient() async {
        for outcome in [PersonalAgentReadResult.Outcome.failed, .budgetExceeded] {
            let reader = PersonalAgentFakeReader()
            await reader.setResult(.init(outcome: outcome), for: .muse)
            let monitor = makeMonitor(reader)
            let owner = NSObject()
            monitor.acquire(owner)
            monitor.setEnabled(true, for: .muse)
            monitor.setEnabled(true, for: .grokBot)
            await monitor.refreshNow()
            XCTAssertEqual(monitor.observations.map(\.client), [.grokBot])
            XCTAssertEqual(monitor.health[.grokBot]?.phase, .observing)
            XCTAssertTrue(
                [PersonalAgentHealthPhase.readFailed, .budgetExceeded].contains(monitor.health[.muse]!.phase))
            monitor.shutdown()
        }
    }

    func testInterfaceSwitchClearsOldActivitiesWhileKeepingCurrentBot() async {
        let reader = PersonalAgentFakeReader()
        let monitor = makeMonitor(reader)
        let owner = NSObject()
        monitor.acquire(owner)
        monitor.setEnabled(true, for: .muse)
        await monitor.refreshNow()
        XCTAssertFalse(monitor.observations.isEmpty)
        await reader.setResult(
            .init(outcome: .success, windows: [PersonalAgentSyntheticUI.muse(selected: false)]), for: .muse)
        await monitor.refreshNow()
        XCTAssertEqual(monitor.observations.count, 1)
        XCTAssertTrue(monitor.observations[0].nativeActivityLabels.isEmpty)
        XCTAssertEqual(monitor.health[.muse]?.phase, .observing)
        XCTAssertNotNil(monitor.health[.muse]?.lastSuccessfulRead)
        await reader.setResult(.init(outcome: .success, windows: [.init(role: "AXWindow")]), for: .muse)
        await monitor.refreshNow()
        XCTAssertTrue(monitor.observations.isEmpty)
        XCTAssertEqual(monitor.health[.muse]?.phase, .interfaceUnavailable)
        monitor.shutdown()
    }

    func testShutdownRejectsOldReadAndCannotBeReopened() async {
        let reader = PersonalAgentFakeReader()
        let gate = PersonalAgentTestGate()
        await reader.setGate(gate)
        let monitor = makeMonitor(reader)
        let owner = NSObject()
        monitor.acquire(owner)
        monitor.setEnabled(true, for: .muse)
        let read = Task { await monitor.refreshNow() }
        await gate.waitUntilEntered()
        monitor.shutdown()
        await gate.open()
        await read.value
        monitor.acquire(owner)
        monitor.setEnabled(true, for: .muse)
        monitor.setSuspended(false)
        await monitor.refreshNow()
        XCTAssertTrue(monitor.observations.isEmpty)
        let calls = await reader.calls
        XCTAssertEqual(calls.count, 1)
    }

    func testFixturesAndHostedWindowsNeverAcquireLiveSources() async {
        let reader = PersonalAgentFakeReader()
        let monitor = PersonalAgentMonitor(
            reader: reader, defaults: nil, runtimeAllowed: { false },
            permission: {
                XCTFail("No live permission read")
                return false
            },
            application: { _ in
                XCTFail("No client lookup")
                return nil
            }, automaticallySchedules: false)
        let owner = NSObject()
        monitor.acquire(owner)
        monitor.setEnabled(true, for: .muse)
        await monitor.refreshNow()
        let calls = await reader.calls
        XCTAssertTrue(calls.isEmpty)
        monitor.shutdown()
    }

    func testMuse60UsesItsOwnContractAndLeavesGrokBotIndependent() async {
        let reader = PersonalAgentFakeReader()
        await reader.setResult(.init(outcome: .success, windows: [PersonalAgentSyntheticUI.muse60]), for: .muse)
        let monitor = makeMonitor(
            reader,
            application: { client in
                .init(
                    client: client, processID: 999_999, bundleID: client.bundleID,
                    version: client == .muse ? "6.0" : "0.68.1")
            })
        let owner = NSObject()
        monitor.acquire(owner)
        monitor.setEnabled(true, for: .muse)
        monitor.setEnabled(true, for: .grokBot)
        await monitor.refreshNow()
        XCTAssertEqual(monitor.observations.map(\.client), [.muse, .grokBot])
        XCTAssertEqual(monitor.health[.muse]?.version, "6.0")
        XCTAssertEqual(monitor.health[.muse]?.phase, .observing)
        XCTAssertTrue(monitor.unavailableClients.isEmpty)
        await reader.setResult(.init(outcome: .success, windows: [PersonalAgentSyntheticUI.muse]), for: .muse)
        await monitor.refreshNow()
        XCTAssertEqual(monitor.observations.map(\.client), [.grokBot])
        XCTAssertEqual(monitor.health[.muse]?.phase, .interfaceUnavailable)
        XCTAssertEqual(monitor.unavailableClients, [.muse])
        monitor.shutdown()
    }

    func testMissingSourceStateIsVisibleWithoutCreatingOrCountingASession() async {
        let reader = PersonalAgentFakeReader()
        let monitor = makeMonitor(reader, permission: { false })
        let owner = NSObject()
        monitor.acquire(owner)
        monitor.setEnabled(true, for: .muse)
        monitor.setEnabled(true, for: .grokBot)
        await monitor.refreshNow()
        XCTAssertTrue(monitor.observations.isEmpty)
        XCTAssertEqual(monitor.unavailableClients, [.muse, .grokBot])
        XCTAssertEqual(monitor.health[.muse]?.phase, .permissionRequired)
        monitor.setEnabled(false, for: .muse)
        XCTAssertEqual(monitor.unavailableClients, [.grokBot])
        monitor.setEnabled(true, for: .dot)
        XCTAssertEqual(monitor.unavailableClients, [.grokBot])
        monitor.shutdown()
    }

    private func makeMonitor(
        _ reader: PersonalAgentFakeReader,
        permission: @escaping @MainActor () -> Bool = { true },
        application: @escaping @MainActor (PersonalAgentClient) -> PersonalAgentApplication? = PersonalAgentMonitorTests
            .application
    ) -> PersonalAgentMonitor {
        PersonalAgentMonitor(
            reader: reader, defaults: nil, runtimeAllowed: { true }, permission: permission,
            application: application, automaticallySchedules: false)
    }

    private static func application(_ client: PersonalAgentClient) -> PersonalAgentApplication? {
        .init(
            client: client, processID: 999_999, bundleID: client.bundleID,
            version: client == .muse ? "4.1" : client == .grokBot ? "0.68.1" : "")
    }
}

private actor PersonalAgentFakeReader: PersonalAgentReading {
    var calls: [PersonalAgentClient] = []
    var results: [PersonalAgentClient: PersonalAgentReadResult] = [:]
    var gate: PersonalAgentTestGate?
    func setGate(_ gate: PersonalAgentTestGate) { self.gate = gate }
    func setResult(_ result: PersonalAgentReadResult, for client: PersonalAgentClient) { results[client] = result }
    func read(_ application: PersonalAgentApplication) async -> PersonalAgentReadResult {
        calls.append(application.client)
        if let gate { await gate.enterAndWait() }
        return results[application.client]
            ?? .init(
                outcome: .success,
                windows: [
                    application.client == .muse ? PersonalAgentSyntheticUI.muse : PersonalAgentSyntheticUI.grok
                ])
    }
}

private actor PersonalAgentTestGate {
    private var entered = false
    private var opened = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var readWaiters: [CheckedContinuation<Void, Never>] = []
    func enterAndWait() async {
        entered = true
        for waiter in entryWaiters { waiter.resume() }
        entryWaiters.removeAll()
        if !opened { await withCheckedContinuation { readWaiters.append($0) } }
    }
    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { entryWaiters.append($0) } }
    }
    func open() {
        opened = true
        for waiter in readWaiters { waiter.resume() }
        readWaiters.removeAll()
    }
}

@MainActor
private final class PersonalAgentTestValue<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}
