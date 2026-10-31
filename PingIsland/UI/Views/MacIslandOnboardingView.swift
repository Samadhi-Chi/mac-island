import AppKit
import SwiftUI

@MainActor
final class MacIslandOnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MacIslandOnboardingWindowController()
    private let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private var completion: ((MacIslandOnboardingCompletion) -> Void)?

    private init() {
        let window = SettingsPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 540),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "Mac Island"
        window.contentViewController = hostingController
        window.identifier = NSUserInterfaceItemIdentifier("mac-island.onboarding.window")
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(onComplete: @escaping (MacIslandOnboardingCompletion) -> Void) {
        completion = onComplete
        hostingController.rootView = AnyView(
            AppLocalizedRootView {
                MacIslandOnboardingView(initialMode: AppSettings.surfaceMode) { [weak self] result in
                    self?.finish(result)
                }
            }.id(UUID()))
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(MacIslandOnboardingCompletion(mode: AppSettings.surfaceMode, action: .finish))
        return false
    }

    private func finish(_ result: MacIslandOnboardingCompletion) {
        let completion = completion
        self.completion = nil
        window?.orderOut(nil)
        completion?(result)
    }
}

struct MacIslandOnboardingView: View {
    @State private var mode: IslandSurfaceMode
    @State private var step = 0
    @State private var health: MacIslandOnboardingHealth?
    @State private var isRefreshing = false
    let onComplete: (MacIslandOnboardingCompletion) -> Void

    init(initialMode: IslandSurfaceMode, onComplete: @escaping (MacIslandOnboardingCompletion) -> Void) {
        _mode = State(initialValue: initialMode)
        self.onComplete = onComplete
    }

    private var title: String {
        switch step {
        case 0: "选择 Mac Island 的位置"
        case 1: "连接你使用的客户端"
        default: "查看连接状态"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Mac Island").font(.headline)
                Spacer()
                Text("\(step + 1) / 3").monospacedDigit().foregroundStyle(.secondary)
            }
            Text(appLocalized: title).font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if step == 0 { presentationStep } else if step == 1 { integrationStep } else { healthStep }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button(AppLocalization.string("稍后设置")) { finish(.finish) }
                    .accessibilityIdentifier("onboarding.skip")
                Spacer()
                if step > 0 {
                    Button(AppLocalization.string("上一步")) { step -= 1 }
                }
                if step < 2 {
                    Button(AppLocalization.string("继续")) { step += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(AppLocalization.string("打开集成设置")) { finish(.integrations) }
                        .accessibilityIdentifier("onboarding.integrations")
                    Button(AppLocalization.string("mac-island.action.done")) { finish(.finish) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 640, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: step) {
            if step == 2 { await refreshHealth() }
        }
    }

    private var presentationStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(appLocalized: "Mac Island 在本机观察任务进度。需要时悬停或点击查看详情，并返回原客户端继续操作。")
                .foregroundStyle(.secondary)
            modeChoice(.notch, title: "屏幕顶部", detail: "固定在屏幕顶部，适合希望保持桌面整洁的使用方式。", symbol: "menubar.rectangle")
            modeChoice(
                .floatingPet, title: "悬浮 Island", detail: "可拖动的小窗口，适合外接显示器或多窗口工作。", symbol: "rectangle.on.rectangle")
            Text(appLocalized: "保持静音；新活动不会自动展开详情。你可以随时在设置中切换位置。")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func modeChoice(_ value: IslandSurfaceMode, title: String, detail: String, symbol: String) -> some View {
        Button {
            mode = value
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title2).frame(width: 38)
                VStack(alignment: .leading, spacing: 5) {
                    Text(appLocalized: title).font(.headline)
                    Text(appLocalized: detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: mode == value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(mode == value ? Color.accentColor : Color.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12).strokeBorder(
                    mode == value ? Color.accentColor : Color.secondary.opacity(0.2))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.mode.\(value.rawValue)")
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }

    private var integrationStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            explanation("Codex 与 Cursor", detail: "已安装的桌面客户端可通过本机只读来源观察。没有活动会话时，列表可以为空。", symbol: "desktopcomputer")
            explanation("CLI 与其他支持的客户端", detail: "在集成设置中选择你需要的客户端，再明确安装对应集成。这里只介绍步骤，不修改客户端配置。", symbol: "terminal")
            explanation(
                "Muse 与 Grok Bot（实验）", detail: "默认关闭。需要单独启用并授权辅助功能；仅观察已验证版本的当前界面，不保证后台任务或运行状态。", symbol: "flask")
            Text(appLocalized: "审批、回复和任务执行始终留在原客户端。设置中会说明每项权限的用途，由你决定是否开启。")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var healthStep: some View {
        if let health {
            explanation("Codex 只读连接", detail: health.codexDescriptionKey, symbol: "network")
            explanation(
                "可选的本机集成",
                detail: health.isPreview
                    ? "预览模式：未读取真实连接"
                    : (health.hasInstalledIntegrations ? "检测到已安装集成；实际状态请在集成设置中确认。" : "未检测到已安装集成；仅在需要对应客户端时，前往集成设置安装。"),
                symbol: "puzzlepiece.extension")
        } else {
            ProgressView(AppLocalization.string("正在读取已有连接状态…"))
        }
        Text(appLocalized: "这些结果只是现有连接的快照，不代表所有客户端都已配置。刷新不会安装集成、申请权限或启动任务。")
            .font(.callout).foregroundStyle(.secondary)
        HStack {
            Button(AppLocalization.string("刷新状态")) { Task { await refreshHealth() } }
                .disabled(isRefreshing)
            Button(AppLocalization.string("查看监控演示")) { finish(.demo) }
        }
    }

    private func explanation(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(appLocalized: title).font(.headline)
                Text(appLocalized: detail).font(.callout).foregroundStyle(.secondary).fixedSize(
                    horizontal: false, vertical: true)
            }
        }
    }

    private func finish(_ action: MacIslandOnboardingCompletion.Action) {
        onComplete(MacIslandOnboardingCompletion(mode: mode, action: action))
    }

    @MainActor
    private func refreshHealth() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        guard SessionMonitor.allowsLiveMonitoring() else {
            health = MacIslandOnboardingHealth(isPreview: true)
            return
        }
        let codex = await CodexReadOnlyClient.shared.healthSnapshot()
        guard !Task.isCancelled else { return }
        // Inspect installation metadata only. bridgeHealthStatus additionally
        // executes a launcher self-check and belongs to the explicit Settings action.
        health = MacIslandOnboardingHealth(codex: codex, hasInstalledIntegrations: HookInstaller.isInstalled())
    }
}
