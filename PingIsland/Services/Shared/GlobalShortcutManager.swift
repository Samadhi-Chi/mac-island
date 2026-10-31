import AppKit
import Carbon.HIToolbox
import Combine

extension Notification.Name {
    static let pingIslandOpenActiveSessionShortcut = Notification.Name("pingIslandOpenActiveSessionShortcut")
    static let pingIslandOpenSessionListShortcut = Notification.Name("pingIslandOpenSessionListShortcut")
    static let pingIslandReturnToSessionShortcut = Notification.Name("pingIslandReturnToSessionShortcut")
    static let pingIslandNextAttentionSessionShortcut = Notification.Name("pingIslandNextAttentionSessionShortcut")
    static let pingIslandPresentNotchDetachmentHint = Notification.Name("pingIslandPresentNotchDetachmentHint")
}

enum GlobalShortcutRegistrationState: Equatable {
    case unassigned
    case registered
    case conflict(GlobalShortcutAction)
    case registrationFailed(OSStatus)
}

@MainActor
final class GlobalShortcutManager: ObservableObject {
    static let shared = GlobalShortcutManager()

    @Published private(set) var registrationStates: [GlobalShortcutAction: GlobalShortcutRegistrationState] = [:]

    private var hotKeyRefs: [GlobalShortcutAction: EventHotKeyRef] = [:]
    private var registeredActionsByHotKeyID: [UInt32: GlobalShortcutAction] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var cancellables = Set<AnyCancellable>()
    private let signature = GlobalShortcutManager.fourCharCode(from: "PISL")
    private var nextHotKeyID: UInt32 = 100
    private var configuredShortcuts: [GlobalShortcutAction: GlobalShortcut] = [:]
    private var registerOverride: ((GlobalShortcut, GlobalShortcutAction) -> OSStatus)?
    private var unregisterOverride: (() -> Void)?

    private init() {
        observe(AppSettings.shared)
    }

    // No actor-bound teardown is required. Avoid the Swift 6.2 implicit isolated
    // deinit back-deployment crash on synchronous release (swiftlang/swift#85663).
    nonisolated deinit {}

    /// Inject registration to exercise conflicts and OS failures without claiming real hotkeys.
    init(
        settings: AppSettingsStore,
        registerShortcut: @escaping (GlobalShortcut, GlobalShortcutAction) -> OSStatus,
        unregisterShortcuts: @escaping () -> Void
    ) {
        registerOverride = registerShortcut
        unregisterOverride = unregisterShortcuts
        observe(settings)
    }

    private func observe(_ settings: AppSettingsStore) {
        Publishers.CombineLatest4(
            settings.$openActiveSessionShortcut,
            settings.$openSessionListShortcut,
            settings.$returnToSessionShortcut,
            settings.$nextAttentionSessionShortcut
        )
        .sink { [weak self] active, list, returnToSession, nextAttention in
            // @Published emits before the stored property changes. Use these values,
            // not a reread of settings, so registration follows the current edit.
            let shortcuts: [GlobalShortcutAction: GlobalShortcut?] = [
                .openActiveSession: active,
                .openSessionList: list,
                .returnToSession: returnToSession,
                .nextAttentionSession: nextAttention,
            ]
            self?.configuredShortcuts = shortcuts.compactMapValues { $0 }
            self?.refreshRegistrations()
        }
        .store(in: &cancellables)
    }

    func start() {
        refreshRegistrations()
    }

    func registrationState(for action: GlobalShortcutAction) -> GlobalShortcutRegistrationState {
        registrationStates[action] ?? .unassigned
    }

    private func refreshRegistrations() {
        unregisterAllHotKeys()
        let handlerStatus = registerOverride == nil ? installEventHandlerIfNeeded() : noErr
        var owners: [GlobalShortcut: GlobalShortcutAction] = [:]
        var states: [GlobalShortcutAction: GlobalShortcutRegistrationState] = [:]

        for action in GlobalShortcutAction.allCases {
            guard let shortcut = configuredShortcuts[action] else {
                states[action] = .unassigned
                continue
            }
            if let owner = owners[shortcut] {
                states[action] = .conflict(owner)
                continue
            }
            owners[shortcut] = action
            guard handlerStatus == noErr else {
                states[action] = .registrationFailed(handlerStatus)
                continue
            }
            let status = registerOverride?(shortcut, action) ?? register(shortcut, for: action)
            states[action] = status == noErr ? .registered : .registrationFailed(status)
        }
        registrationStates = states
    }

    private func register(_ shortcut: GlobalShortcut, for action: GlobalShortcutAction) -> OSStatus {
        var hotKeyRef: EventHotKeyRef?
        let carbonID = nextRegistrationID()
        let hotKeyID = EventHotKeyID(signature: signature, id: carbonID)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else { return status }
        guard let hotKeyRef else { return OSStatus(eventNotHandledErr) }
        hotKeyRefs[action] = hotKeyRef
        registeredActionsByHotKeyID[carbonID] = action
        return noErr
    }

    private func unregisterAllHotKeys() {
        unregisterOverride?()
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        registeredActionsByHotKeyID.removeAll()
    }

    private func installEventHandlerIfNeeded() -> OSStatus {
        guard eventHandlerRef == nil else { return noErr }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleHotKeyEvent(event)
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )
        guard status == noErr else { return status }
        return eventHandlerRef == nil ? OSStatus(eventNotHandledErr) : noErr
    }

    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else { return status }
        guard hotKeyID.signature == signature,
            let action = registeredActionsByHotKeyID[hotKeyID.id]
        else {
            return OSStatus(eventNotHandledErr)
        }

        switch action {
        case .openActiveSession:
            NotificationCenter.default.post(name: .pingIslandOpenActiveSessionShortcut, object: nil)
        case .openSessionList:
            NotificationCenter.default.post(name: .pingIslandOpenSessionListShortcut, object: nil)
        case .returnToSession:
            NotificationCenter.default.post(name: .pingIslandReturnToSessionShortcut, object: nil)
        case .nextAttentionSession:
            NotificationCenter.default.post(name: .pingIslandNextAttentionSessionShortcut, object: nil)
        }

        return noErr
    }

    private func nextRegistrationID() -> UInt32 {
        defer {
            nextHotKeyID = nextHotKeyID == UInt32.max ? 100 : nextHotKeyID + 1
        }
        return nextHotKeyID
    }

    private static func fourCharCode(from string: String) -> OSType {
        string.utf8.prefix(4).reduce(0) { partial, character in
            (partial << 8) + OSType(character)
        }
    }
}
