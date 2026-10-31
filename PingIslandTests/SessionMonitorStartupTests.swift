import XCTest

@testable import Ping_Island

final class SessionMonitorStartupTests: XCTestCase {
    func testNormalLaunchAllowsMonitoring() {
        XCTAssertTrue(SessionMonitor.allowsLiveMonitoring(environment: [:], hasXCTestRuntime: false))
    }

    func testHostedTestsAreIsolatedWithoutConfigurationEnvironmentVariable() {
        XCTAssertFalse(SessionMonitor.allowsLiveMonitoring(environment: [:], hasXCTestRuntime: true))
    }

    func testXCTestConfigurationDisablesMonitoring() {
        XCTAssertFalse(
            SessionMonitor.allowsLiveMonitoring(
                environment: ["XCTestConfigurationFilePath": "/tmp/fixture.xctestconfiguration"],
                hasXCTestRuntime: false
            ))
    }

    func testUITestModeDisablesMonitoring() {
        XCTAssertFalse(
            SessionMonitor.allowsLiveMonitoring(
                environment: ["PING_ISLAND_UI_TEST_MODE": "1"], hasXCTestRuntime: false
            ))
    }

    func testFixturePlaybackDisablesMonitoringEvenWithNormalWindows() {
        XCTAssertFalse(
            SessionMonitor.allowsLiveMonitoring(
                environment: ["MAC_ISLAND_FIXTURE_PATH": "/tmp/island-fixture.json"], hasXCTestRuntime: false
            ))
        XCTAssertTrue(
            SessionMonitor.allowsLiveMonitoring(
                environment: ["MAC_ISLAND_FIXTURE_PATH": ""], hasXCTestRuntime: false
            ))
    }

    @MainActor
    func testHostedWindowCannotStartLiveIngress() {
        let monitor = SessionMonitor(observeSharedState: false)
        monitor.startMonitoring()
        XCTAssertFalse(monitor.hasStarted)
    }

    @MainActor
    func testHostedListCannotStartLiveQuotaRefresh() {
        let monitor = SessionMonitor(observeSharedState: false)
        monitor.refreshUsageState()
        XCTAssertFalse(monitor.isUsageRefreshScheduled)
        XCTAssertFalse(monitor.hasStarted)
    }

    @MainActor
    func testSynchronousLifecycleReleaseClearsWeakRegistration() {
        weak var releasedShutdown: SessionMonitoringShutdown?
        weak var releasedLifecycle: SessionMonitoringLifecycle?
        autoreleasepool {
            let shutdown = SessionMonitoringShutdown()
            releasedShutdown = shutdown
            autoreleasepool {
                let lifecycle = SessionMonitoringLifecycle(shutdown: shutdown)
                releasedLifecycle = lifecycle
                XCTAssertTrue(lifecycle.start())
                lifecycle.stop()
            }
            XCTAssertNil(releasedLifecycle)
            // The boundary remains usable after its weakly registered owner exits.
            shutdown.begin()
        }
        XCTAssertNil(releasedShutdown)
    }

    @MainActor
    func testApplicationShutdownCancelsQueuedLaunchAndWindowStarts() async {
        let shutdown = SessionMonitoringShutdown()
        let launchMonitor = SessionMonitoringLifecycle(shutdown: shutdown)
        let windowMonitor = SessionMonitoringLifecycle(shutdown: shutdown)
        var starts = 0
        var localStops = 0
        launchMonitor.onStop = { localStops += 1 }
        windowMonitor.onStop = { localStops += 1 }
        XCTAssertTrue(launchMonitor.start())
        XCTAssertTrue(windowMonitor.start())
        let launchTask = launchMonitor.enqueue { starts += 1 }
        let windowTask = windowMonitor.enqueue { starts += 1 }

        // Quit happens in the same main-actor turn, before either task runs.
        shutdown.begin()
        shutdown.begin()
        await launchTask?.value
        await windowTask?.value

        XCTAssertEqual(starts, 0)
        XCTAssertEqual(localStops, 2)
        XCTAssertFalse(launchMonitor.hasStarted)
        XCTAssertFalse(windowMonitor.hasStarted)
        XCTAssertFalse(launchMonitor.start())
        XCTAssertFalse(SessionMonitoringLifecycle(shutdown: shutdown).start())
    }

    @MainActor
    func testApplicationShutdownCompensatesForCancellationIgnoringStartup() async {
        let shutdown = SessionMonitoringShutdown()
        let monitor = SessionMonitoringLifecycle(shutdown: shutdown)
        let entered = SessionMonitorStartupLatch()
        let release = SessionMonitorStartupLatch()
        var serviceIsRunning = false
        var stops = 0
        XCTAssertTrue(monitor.start())
        let task = monitor.enqueue {
            await entered.open()
            // Models a start already queued on another actor before quit.
            await release.wait()
            serviceIsRunning = true
        } onStopped: {
            serviceIsRunning = false
            stops += 1
        }
        await entered.wait()

        shutdown.begin()
        await release.open()
        await task?.value

        XCTAssertFalse(serviceIsRunning)
        XCTAssertEqual(stops, 1)
        XCTAssertNil(monitor.enqueue { serviceIsRunning = true })
    }

    @MainActor
    func testApplicationShutdownCancelsInFlightEnergyResume() async {
        let shutdown = SessionMonitoringShutdown()
        let monitor = SessionMonitoringLifecycle(shutdown: shutdown)
        let entered = SessionMonitorStartupLatch()
        var observedCancellation = false
        XCTAssertTrue(monitor.start())
        let task = monitor.enqueue {
            await entered.open()
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                observedCancellation = Task.isCancelled
            }
        }
        await entered.wait()

        shutdown.begin()
        await task?.value

        XCTAssertTrue(observedCancellation)
        XCTAssertNil(monitor.enqueue {})
    }

    @MainActor
    func testOrdinaryStopAllowsRestartWithoutOldStartupStoppingNewGeneration() async {
        let monitor = SessionMonitoringLifecycle(shutdown: SessionMonitoringShutdown())
        let entered = SessionMonitorStartupLatch()
        let release = SessionMonitorStartupLatch()
        var stops = 0
        XCTAssertTrue(monitor.start())
        XCTAssertFalse(monitor.start())
        let oldStartup = monitor.enqueue {
            await entered.open()
            await release.wait()
        } onStopped: {
            stops += 1
        }
        await entered.wait()

        monitor.stop()
        XCTAssertTrue(monitor.start())
        await release.open()
        await oldStartup?.value

        XCTAssertTrue(monitor.hasStarted)
        XCTAssertEqual(stops, 0)
        monitor.stop()
    }
}

private actor SessionMonitorStartupLatch {
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
