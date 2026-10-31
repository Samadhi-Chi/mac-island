import XCTest

@testable import Ping_Island

@MainActor
final class MacIslandOnboardingTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "MacIslandOnboardingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }

    func testFreshInstallShowsOnboardingWhileAutomaticHooksRemainDisabled() {
        withDefaults { defaults in
            MacIslandOnboardingState.prepareForLaunch(defaults: defaults, isInteractiveLaunch: true)
            let configuration = AppLaunchConfiguration(environment: [:], isDebuggerAttached: false)
            let flow = AppLaunchFlow(
                configuration: configuration,
                presentationModeOnboardingPending: defaults.bool(forKey: MacIslandOnboardingState.pendingKey))
            XCTAssertFalse(configuration.shouldInstallIntegrations)
            XCTAssertTrue(flow.shouldPresentSurfaceModeOnboarding)
            XCTAssertFalse(flow.shouldCreateInitialIslandWindow)
            XCTAssertNil(defaults.object(forKey: "hookInstallOnboardingPending"))
        }
    }

    func testInterruptedFirstRunRemainsPendingAfterSettingsWriteTheirDefaults() {
        withDefaults { defaults in
            MacIslandOnboardingState.prepareForLaunch(defaults: defaults, isInteractiveLaunch: true)
            defaults.set(3, forKey: "macIslandDefaultsVersion")
            MacIslandOnboardingState.prepareForLaunch(defaults: defaults, isInteractiveLaunch: true)
            XCTAssertTrue(defaults.bool(forKey: MacIslandOnboardingState.pendingKey))
            XCTAssertFalse(defaults.bool(forKey: MacIslandOnboardingState.completedKey))
        }
    }

    func testExistingDevelopmentInstallationDoesNotReceiveNewWelcomeWindow() {
        withDefaults { defaults in
            defaults.set(3, forKey: "macIslandDefaultsVersion")
            MacIslandOnboardingState.prepareForLaunch(defaults: defaults, isInteractiveLaunch: true)
            XCTAssertFalse(defaults.bool(forKey: MacIslandOnboardingState.pendingKey))
            XCTAssertTrue(defaults.bool(forKey: MacIslandOnboardingState.completedKey))
        }
    }

    func testExistingSurfaceChoiceIsPreservedWithoutReplay() {
        withDefaults { defaults in
            defaults.set("floatingPet", forKey: "surfaceMode")
            MacIslandOnboardingState.prepareForLaunch(defaults: defaults, isInteractiveLaunch: true)
            XCTAssertFalse(defaults.bool(forKey: MacIslandOnboardingState.pendingKey))
            XCTAssertEqual(defaults.string(forKey: "surfaceMode"), "floatingPet")
        }
    }

    func testCompletedLegacyOnboardingMigratesWithoutRepeat() {
        withDefaults { defaults in
            defaults.set(false, forKey: MacIslandOnboardingState.pendingKey)
            MacIslandOnboardingState.prepareForLaunch(defaults: defaults, isInteractiveLaunch: true)
            XCTAssertTrue(defaults.bool(forKey: MacIslandOnboardingState.completedKey))
            XCTAssertFalse(defaults.bool(forKey: MacIslandOnboardingState.pendingKey))
        }
    }

    func testCompleteAndSkipPersistAcrossAnotherLaunch() {
        withDefaults { defaults in
            MacIslandOnboardingState.prepareForLaunch(defaults: defaults, isInteractiveLaunch: true)
            MacIslandOnboardingState.complete(defaults: defaults)
            MacIslandOnboardingState.prepareForLaunch(defaults: defaults, isInteractiveLaunch: true)
            XCTAssertFalse(defaults.bool(forKey: MacIslandOnboardingState.pendingKey))
            XCTAssertTrue(defaults.bool(forKey: MacIslandOnboardingState.completedKey))
        }
    }

    func testFixtureAndTestPreparationDoesNotWritePreferences() {
        withDefaults { defaults in
            let before = defaults.dictionaryRepresentation() as NSDictionary
            MacIslandOnboardingState.prepareForLaunch(defaults: defaults, isInteractiveLaunch: false)
            XCTAssertEqual(before, defaults.dictionaryRepresentation() as NSDictionary)
        }
    }

    func testFixtureLaunchNeverStartsMonitoringOrOnboarding() {
        let configuration = AppLaunchConfiguration(
            environment: [MacIslandFixturePlayer.environmentKey: "/synthetic/fixture.json"],
            isDebuggerAttached: false
        )
        let flow = AppLaunchFlow(configuration: configuration, presentationModeOnboardingPending: true)
        XCTAssertTrue(configuration.isFixturePlayback)
        XCTAssertFalse(configuration.shouldInstallIntegrations)
        XCTAssertFalse(flow.shouldPresentSurfaceModeOnboarding)
        XCTAssertFalse(flow.shouldStartMonitoringImmediately)
        XCTAssertTrue(flow.shouldCreateInitialIslandWindow)
    }

    func testHostedTestLaunchCannotShowOnboarding() {
        let configuration = AppLaunchConfiguration(
            environment: ["XCTestConfigurationFilePath": "/synthetic/tests.xctestconfiguration"],
            isDebuggerAttached: false
        )
        let flow = AppLaunchFlow(configuration: configuration, presentationModeOnboardingPending: true)
        XCTAssertFalse(flow.shouldStartMonitoringImmediately)
        XCTAssertFalse(flow.shouldPresentSurfaceModeOnboarding)
        XCTAssertFalse(flow.shouldCreateInitialIslandWindow)
    }

    func testConnectedHealthDoesNotClaimSuccessfulReadBeforeEvidence() {
        var health = MacIslandOnboardingHealth()
        health.codex.phase = .connected
        XCTAssertEqual(health.codexDescriptionKey, "Codex 已连接，等待首次读取")
        health.codex.lastSuccessfulRead = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(health.codexDescriptionKey, "Codex 已成功读取；暂无会话也属于正常情况")
    }

    func testPreviewHealthDoesNotClaimRealConnection() {
        var health = MacIslandOnboardingHealth(isPreview: true)
        health.codex.phase = .connected
        health.codex.lastSuccessfulRead = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(health.codexDescriptionKey, "预览模式：未读取真实连接")
    }

    func testDemoAlwaysCompletesWithoutAnAgentApprovalOrConnection() {
        var demo = MacIslandMonitorDemo()
        XCTAssertEqual(demo.stage, .working)
        demo.advance()
        XCTAssertEqual(demo.stage, .attention)
        demo.advance()
        XCTAssertEqual(demo.stage, .complete)
        demo.advance()
        XCTAssertEqual(demo.stage, .complete)
    }
}
