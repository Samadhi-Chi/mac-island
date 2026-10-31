import Combine
import XCTest

@testable import Ping_Island

@MainActor
final class ScreenPrivacyTests: XCTestCase {
    func testSettingsStoreCanReleaseAfterScopedInitialization() {
        withDefaults { defaults in
            weak var releasedStore: AppSettingsStore?
            autoreleasepool {
                let store = AppSettingsStore(defaults: defaults, bridgeRuntimeConfigWriter: { _ in })
                releasedStore = store
                XCTAssertNotNil(releasedStore)
            }
            XCTAssertNil(releasedStore)
        }
    }

    func testFreshSettingsInitializationDefaultsToTitlesBeforePresetStamp() {
        withDefaults { defaults in
            _ = AppSettingsStore(defaults: defaults, bridgeRuntimeConfigWriter: { _ in })
            XCTAssertEqual(ScreenPrivacyStore(defaults: defaults).mode, .titles)
            XCTAssertGreaterThan(defaults.integer(forKey: "macIslandDefaultsVersion"), 0)
        }
    }

    func testUpgradePreservesRichPresentationAndNeverOverridesLaterChoice() {
        withDefaults { defaults in
            defaults.set(3, forKey: "macIslandDefaultsVersion")
            _ = AppSettingsStore(defaults: defaults, bridgeRuntimeConfigWriter: { _ in })
            let store = ScreenPrivacyStore(defaults: defaults)
            XCTAssertEqual(store.mode, .details)
            store.mode = .statusOnly
            _ = AppSettingsStore(defaults: defaults, bridgeRuntimeConfigWriter: { _ in })
            XCTAssertEqual(ScreenPrivacyStore(defaults: defaults).mode, .statusOnly)
        }
    }

    func testUnknownPreferenceDoesNotEnableRichContent() {
        withDefaults { defaults in
            defaults.set("future-or-corrupt-value", forKey: ScreenContentVisibility.settingsKey)
            ScreenContentVisibility.preparePreference(defaults: defaults, previousPresetVersion: 3)
            XCTAssertEqual(ScreenPrivacyStore(defaults: defaults).effectiveMode, .titles)
        }
    }

    func testTemporaryHidingPublishesAndRestoresWithoutChangingSavedChoice() {
        withDefaults { defaults in
            let store = ScreenPrivacyStore(defaults: defaults)
            store.mode = .details
            var changes = 0
            let subscription = store.objectWillChange.sink { changes += 1 }
            store.toggleTemporaryHiding()
            XCTAssertEqual(store.effectiveMode, .statusOnly)
            XCTAssertEqual(defaults.string(forKey: ScreenContentVisibility.settingsKey), "details")
            XCTAssertFalse(ScreenPrivacyStore(defaults: defaults).isTemporarilyHidden)
            store.mode = .titles
            XCTAssertEqual(store.effectiveMode, .statusOnly)
            store.toggleTemporaryHiding()
            XCTAssertEqual(store.effectiveMode, .titles)
            XCTAssertEqual(changes, 3)
            withExtendedLifetime(subscription) {}
        }
    }

    func testRestrictedRowsNeverDeriveTitleFromPromptPathOrClientLabel() {
        var session = fixture()
        session.previewText = "PRIVATE_PROMPT"
        session.clientInfo.name = "PRIVATE_CLIENT_LABEL"
        session.sessionName = nil
        for mode in [ScreenContentVisibility.statusOnly, .titles] {
            let row = ScreenSessionPresentation(session: session, title: .unavailable, mode: mode)
            XCTAssertNil(row.title)
            XCTAssertEqual(row.clientName, "Codex")
            XCTAssertEqual(row.statusKey, "screen-privacy.status.working")
        }
        let native = ScreenSessionPresentation(session: session, title: .native("Original title"), mode: .titles)
        XCTAssertEqual(native.title, "Original title")
        XCTAssertNil(
            ScreenSessionPresentation(session: session, title: .native("Original title"), mode: .statusOnly).title)
    }

    func testRecentRowsHideIdentityAndDoNotSubstituteWorkspaceForMissingTitle() {
        let record = RecentSessionRecord(
            sessionID: "PRIVATE_ID", nativeSessionID: "PRIVATE_ID",
            client: .codexDesktop, origin: "desktop", workspace: "/tmp/PRIVATE_PROJECT", lastActivity: Date())
        let unnamed = ScreenSessionPresentation(record: record, title: .unavailable, mode: .titles)
        XCTAssertNil(unnamed.title)
        XCTAssertEqual(unnamed.clientName, "Codex")
        XCTAssertEqual(unnamed.statusKey, "screen-privacy.status.recent")
        XCTAssertNil(
            ScreenSessionPresentation(record: record, title: .native("PRIVATE_TITLE"), mode: .statusOnly).title)
    }

    func testBothBotSourcesHideNamesAndActivityAtRequestedLevels() {
        for client in [PersonalAgentClient.muse, .grokBot] {
            let observation = PersonalAgentObservation(
                id: "ephemeral", client: client,
                agentName: "PRIVATE_BOT", nativeTaskTitle: "PRIVATE_TASK",
                nativeActivityLabels: ["PRIVATE_ACTIVITY"], scope: .visibleActivity, observedAt: Date())
            let status = ScreenPersonalAgentPresentation(
                observation: observation, mode: .statusOnly, unavailableName: "Unavailable")
            XCTAssertEqual(status.name, client.name)
            XCTAssertTrue(status.activities.isEmpty)
            let titles = ScreenPersonalAgentPresentation(
                observation: observation, mode: .titles, unavailableName: "Unavailable")
            XCTAssertEqual(titles.name, "PRIVATE_BOT")
            XCTAssertTrue(titles.activities.isEmpty)
            let details = ScreenPersonalAgentPresentation(
                observation: observation, mode: .details, unavailableName: "Unavailable")
            XCTAssertEqual(details.activities, ["PRIVATE_ACTIVITY"])
        }
    }

    func testEveryExpandedEntryUsesSafeListWhenContentIsRestricted() {
        let session = fixture()
        let notification = SessionCompletionNotification(session: session, kind: .completed)
        for mode in [ScreenContentVisibility.statusOnly, .titles] {
            for surface in [IslandExpandedSurface.docked, .floating] {
                for trigger in [IslandExpandedTrigger.click, .hover, .notification, .pinnedList] {
                    for content in [NotchContentType.instances, .chat(session)] {
                        XCTAssertEqual(
                            IslandExpandedRouteResolver.resolve(
                                surface: surface, trigger: trigger, contentType: content,
                                sessions: [session], activeCompletionNotification: notification,
                                contentVisibility: mode
                            ), .sessionList)
                    }
                }
            }
        }
        XCTAssertEqual(
            IslandExpandedRouteResolver.resolve(
                surface: .floating, trigger: .hover,
                contentType: .chat(session), sessions: [session], contentVisibility: .details), .chat(session))
    }

    private func fixture() -> SessionState {
        SessionState(
            sessionId: "PRIVATE_ID", cwd: "/tmp/PRIVATE_PROJECT", provider: .codex,
            clientInfo: .codexApp(threadId: "PRIVATE_ID"), phase: .processing)
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "ScreenPrivacyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }
}
