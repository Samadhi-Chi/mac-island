import AppKit
import XCTest

@testable import Ping_Island

final class GlobalShortcutTests: XCTestCase {
    func testGlobalShortcutRequiresModifierKeys() {
        XCTAssertNil(GlobalShortcut(keyCode: 38, modifierFlags: []))
    }

    func testGlobalShortcutSanitizesToSupportedModifiersAndFormatsDisplayString() {
        let shortcut = GlobalShortcut(
            keyCode: 38,
            modifierFlags: [.control, .option, .command, .capsLock]
        )

        XCTAssertNotNil(shortcut)
        XCTAssertEqual(shortcut?.modifierFlags, [.control, .option, .command])
        XCTAssertEqual(shortcut?.displayParts, ["\u{2303}", "\u{2325}", "\u{2318}", "J"])
        XCTAssertEqual(shortcut?.displayString, "\u{2303} \u{2325} \u{2318} J")
    }

    func testDefaultShortcutsRemainDistinct() {
        XCTAssertNotEqual(
            GlobalShortcutAction.openActiveSession.defaultShortcut,
            GlobalShortcutAction.openSessionList.defaultShortcut
        )
    }

    func testDefaultShortcutsUseOptionModifier() {
        XCTAssertEqual(
            GlobalShortcutAction.openActiveSession.defaultShortcut?.modifierFlags,
            [.option]
        )
        XCTAssertEqual(
            GlobalShortcutAction.openSessionList.defaultShortcut?.modifierFlags,
            [.option]
        )
    }

    func testNavigationShortcutsHaveNoDefaultBinding() {
        XCTAssertNil(GlobalShortcutAction.returnToSession.defaultShortcut)
        XCTAssertNil(GlobalShortcutAction.nextAttentionSession.defaultShortcut)
        XCTAssertTrue(GlobalShortcutAction.returnToSession.legacyDefaultShortcuts.isEmpty)
        XCTAssertTrue(GlobalShortcutAction.nextAttentionSession.legacyDefaultShortcuts.isEmpty)
    }

    @MainActor
    private static var retainedSettings: [AppSettingsStore] = []

    @MainActor
    private func makeSettings(testName: String = #function) -> AppSettingsStore {
        let suite = "PingIslandTests.GlobalShortcut.\(testName)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettingsStore(defaults: defaults)
        Self.retainedSettings.append(settings)
        return settings
    }

    @MainActor
    func testRegistrationUsesNewPublishedValueImmediatelyAndClearUnregisters() throws {
        let settings = makeSettings()
        var registered: [GlobalShortcutAction: GlobalShortcut] = [:]
        let manager = GlobalShortcutManager(
            settings: settings,
            registerShortcut: { shortcut, action in
                registered[action] = shortcut
                return 0
            },
            unregisterShortcuts: { registered.removeAll() }
        )
        let shortcut = try XCTUnwrap(GlobalShortcut(keyCode: 45, modifierFlags: [.control, .shift]))

        XCTAssertEqual(manager.registrationState(for: .returnToSession), .unassigned)
        settings.setShortcut(shortcut, for: .returnToSession)
        XCTAssertEqual(registered[.returnToSession], shortcut)
        XCTAssertEqual(manager.registrationState(for: .returnToSession), .registered)

        settings.setShortcut(nil, for: .returnToSession)
        XCTAssertNil(registered[.returnToSession])
        XCTAssertEqual(manager.registrationState(for: .returnToSession), .unassigned)
        XCTAssertEqual(registered[.openActiveSession], GlobalShortcutAction.openActiveSession.defaultShortcut)
    }

    @MainActor
    func testRegistrationPublishesOSFailureAndRetryClearsIt() {
        let settings = makeSettings()
        var shouldFail = true
        let manager = GlobalShortcutManager(
            settings: settings,
            registerShortcut: { _, action in
                shouldFail && action == .openActiveSession ? -9878 : 0
            },
            unregisterShortcuts: {}
        )

        XCTAssertEqual(manager.registrationState(for: .openActiveSession), .registrationFailed(-9878))
        XCTAssertEqual(manager.registrationState(for: .openSessionList), .registered)
        shouldFail = false
        manager.start()
        XCTAssertEqual(manager.registrationState(for: .openActiveSession), .registered)
    }

    @MainActor
    func testDuplicatePersistedBindingsReportConflictingOwnerWithoutRegisteringTwice() throws {
        let settings = makeSettings()
        let shortcut = try XCTUnwrap(GlobalShortcutAction.openActiveSession.defaultShortcut)
        // Simulate conflicting persisted settings rather than the editor's deduplicated write.
        settings.returnToSessionShortcut = shortcut
        settings.nextAttentionSessionShortcut = shortcut
        var registered: [GlobalShortcutAction] = []
        let manager = GlobalShortcutManager(
            settings: settings,
            registerShortcut: { _, action in
                registered.append(action)
                return 0
            },
            unregisterShortcuts: { registered.removeAll() }
        )

        XCTAssertEqual(manager.registrationState(for: .returnToSession), .conflict(.openActiveSession))
        XCTAssertEqual(manager.registrationState(for: .nextAttentionSession), .conflict(.openActiveSession))
        XCTAssertEqual(Set(registered), [.openActiveSession, .openSessionList])

        let displaced = settings.setShortcut(shortcut, for: .nextAttentionSession)
        XCTAssertEqual(displaced, [.openActiveSession, .returnToSession])
        XCTAssertEqual(manager.registrationState(for: .nextAttentionSession), .registered)
        XCTAssertEqual(manager.registrationState(for: .openActiveSession), .unassigned)
        XCTAssertEqual(manager.registrationState(for: .returnToSession), .unassigned)
    }

}
