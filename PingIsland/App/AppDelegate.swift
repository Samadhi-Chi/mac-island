import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: WindowManager?
    private var screenObserver: ScreenObserver?
    private let launchConfiguration = AppLaunchConfiguration()
    private let startupSessionMonitor = SessionMonitor()
    private let terminationCoordinator = AppTerminationCoordinator()
    private let globalShortcutManager = GlobalShortcutManager.shared
    private var shouldPresentSettingsAfterOnboarding = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if launchConfiguration.shouldEnforceSingleInstance && !ensureSingleInstance() {
            NSApplication.shared.terminate(nil)
            return
        }

        // Touch the settings store early so the bridge runtime config is on disk
        // before any hook fires.
        _ = AppSettings.shared
        MacIslandFixturePlayer.preparePresentation()
        #if APP_STORE
            HookInstaller.restoreAppStoreHookDirectoryAuthorizationIfAvailable()
        #endif

        // Mac Island V1 is local and monitor-only. Upstream update, telemetry,
        // and approval-routing services intentionally remain dormant.

        // AppSettings prepares first-run UI independently of hook installation.
        // Client configuration changes remain explicit integration-settings actions.

        NSApplication.shared.setActivationPolicy(launchConfiguration.activationPolicy)

        let launchFlow = AppLaunchFlow(
            configuration: launchConfiguration,
            presentationModeOnboardingPending: AppSettings.presentationModeOnboardingPending
        )
        shouldPresentSettingsAfterOnboarding = launchFlow.shouldPresentSettingsWindowAfterOnboarding

        if let fixturePath = Foundation.ProcessInfo.processInfo.environment[MacIslandFixturePlayer.environmentKey],
            !fixturePath.isEmpty
        {
            Task {
                do {
                    try await MacIslandFixturePlayer.play(fileURL: URL(fileURLWithPath: fixturePath))
                    if Foundation.ProcessInfo.processInfo.environment["MAC_ISLAND_FIXTURE_OPEN_LIST"] == "1" {
                        self.windowManager?.presentationCoordinator?.viewModel.presentSessionList(reason: .click)
                    }
                } catch {
                    NSLog("Mac Island fixture failed: \(error.localizedDescription)")
                }
            }
        } else if launchFlow.shouldStartMonitoringImmediately {
            // Keep hook and app-server ingestion alive even when first-run onboarding
            // defers the initial Island window.
            startupSessionMonitor.startMonitoring()
        }

        if launchFlow.shouldCreateInitialIslandWindow {
            startWindowManagerIfNeeded()
        }

        if launchConfiguration.shouldObserveScreens {
            screenObserver = ScreenObserver { [weak self] in
                self?.handleScreenChange()
            }
        }

        if MacIslandRuntimeEnvironment.allowsLiveIO { globalShortcutManager.start() }

        if launchFlow.shouldPresentSurfaceModeOnboarding {
            MacIslandOnboardingWindowController.shared.present { [weak self] result in
                self?.completeOnboarding(result)
            }
        } else if launchFlow.shouldPresentSettingsWindowImmediately {
            SettingsWindowController.shared.present()
        }

        // Play the fixed client startup sound for the bundled 8-bit theme.
        Task { @MainActor in
            AppSettings.playClientStartupSound()
        }

    }

    @MainActor
    private func handleScreenChange() {
        guard !AppSettings.presentationModeOnboardingPending || launchConfiguration.isFixturePlayback else { return }
        startWindowManagerIfNeeded()
    }

    @MainActor
    private func completeOnboarding(_ result: MacIslandOnboardingCompletion) {
        AppSettings.surfaceMode = result.mode
        MacIslandOnboardingState.complete()
        AppSettings.presentationModeOnboardingPending = false
        AppSettings.hookInstallOnboardingPending = false
        AppSettings.notchDetachmentHintPending = false
        AppSettings.floatingPetSettingsHintPending = false
        startWindowManagerIfNeeded()

        switch result.action {
        case .integrations:
            SettingsWindowController.shared.present(category: .integration)
        case .demo:
            HookWalkthroughDemoRunner.shared.start()
        case .finish:
            if shouldPresentSettingsAfterOnboarding {
                SettingsWindowController.shared.present()
            }
        }
        shouldPresentSettingsAfterOnboarding = false
    }

    @MainActor
    private func startWindowManagerIfNeeded() {
        if windowManager == nil {
            windowManager = WindowManager()
        }
        _ = windowManager?.setupNotchWindow()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        SessionMonitor.beginApplicationShutdown()
        return terminationCoordinator.requestTermination(
            cleanup: { [startupSessionMonitor] in
                await startupSessionMonitor.stopMonitoringForTermination()
            },
            reply: { sender.reply(toApplicationShouldTerminate: true) }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        screenObserver = nil
    }
    private func ensureSingleInstance() -> Bool {
        let bundleID = MacIslandProductPolicy.runtimeBundleIdentifier
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID
        }

        if runningApps.count > 1 {
            if let existingApp = runningApps.first(where: { $0.processIdentifier != getpid() }) {
                existingApp.activate()
            }
            return false
        }

        return true
    }
}
