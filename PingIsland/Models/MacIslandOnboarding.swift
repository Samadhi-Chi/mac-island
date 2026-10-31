import Foundation

/// First-run UI has its own lifecycle; observing a client never installs its hooks.
/// Prepare before AppSettings writes its migration defaults so new installations
/// remain distinguishable from existing users upgrading from the development app.
nonisolated enum MacIslandOnboardingState {
    static let completedKey = "macIslandOnboardingCompleted"
    static let pendingKey = "presentationModeOnboardingPending"
    private static let legacyConfigurationKeys: Set<String> = [
        "macIslandDefaultsVersion", "surfaceMode", "subagentVisibilityMode",
        "hookInstallOnboardingPending", "appLanguage", "floatingPetAnchor",
    ]

    static func prepareForLaunch(defaults: UserDefaults, isInteractiveLaunch: Bool) {
        guard isInteractiveLaunch else { return }
        if defaults.bool(forKey: completedKey) {
            defaults.set(false, forKey: pendingKey)
            return
        }
        if defaults.bool(forKey: pendingKey) { return }

        let existingKeys = Set(defaults.dictionaryRepresentation().keys)
        if !legacyConfigurationKeys.isDisjoint(with: existingKeys)
            || existingKeys.contains(pendingKey)
        {
            // An upgrade must not introduce an unsolicited onboarding window.
            complete(defaults: defaults)
        } else {
            defaults.set(true, forKey: pendingKey)
        }
    }

    static func complete(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completedKey)
        defaults.set(false, forKey: pendingKey)
    }
}

struct MacIslandOnboardingCompletion {
    enum Action { case finish, integrations, demo }
    let mode: IslandSurfaceMode
    let action: Action
}

/// This is a snapshot of existing health, not a connection request or diagnosis
/// of every supported client. Missing hooks are optional, never a setup failure.
nonisolated struct MacIslandOnboardingHealth: Equatable, Sendable {
    var codex = CodexMonitorHealth()
    var hasInstalledIntegrations = false
    var isPreview = false

    var codexDescriptionKey: String {
        if isPreview { return "预览模式：未读取真实连接" }
        switch codex.phase {
        case .stopped: return "Codex 观察尚未启动"
        case .connecting: return "正在连接 Codex"
        case .connected:
            return codex.lastSuccessfulRead == nil
                ? "Codex 已连接，等待首次读取"
                : "Codex 已成功读取；暂无会话也属于正常情况"
        case .retrying: return "Codex 连接中断，将自动重试"
        case .suspended: return "系统休眠或锁屏，观察已暂停"
        case .unavailable: return "未找到 Codex；使用其他客户端不受影响"
        }
    }
}

/// Deliberately separate from SessionStore: examples must not become real sessions,
/// trigger native queries, enter recent records, or expose actions on another app.
nonisolated struct MacIslandMonitorDemo: Equatable {
    enum Stage: Int, CaseIterable { case working, attention, complete }
    private(set) var stage: Stage = .working

    mutating func advance() {
        switch stage {
        case .working: stage = .attention
        case .attention: stage = .complete
        case .complete: break
        }
    }
}
