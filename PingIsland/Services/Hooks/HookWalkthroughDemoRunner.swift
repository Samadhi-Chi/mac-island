import AppKit
import SwiftUI

extension Notification.Name {
    // Retained for existing Island view subscribers. The read-only demo does
    // not send this notification or change the real Island's open state.
    static let pingIslandHookWalkthroughDemoShouldCloseNotch = Notification.Name(
        "pingIslandHookWalkthroughDemoShouldCloseNotch")
}

/// Synthetic UI only: no SessionStore entry, client reads, installations,
/// approvals or external tasks. Examples never enter current or recent sessions.
@MainActor
final class HookWalkthroughDemoRunner: NSWindowController, NSWindowDelegate {
    static let shared = HookWalkthroughDemoRunner()
    private let hostingController = NSHostingController(rootView: AnyView(EmptyView()))

    private init() {
        let window = SettingsPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 580),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = AppLocalization.string("Mac Island 监控演示")
        window.contentViewController = hostingController
        window.identifier = NSUserInterfaceItemIdentifier("mac-island.monitor-demo.window")
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func start() {
        hostingController.rootView = AnyView(
            AppLocalizedRootView {
                MacIslandMonitorDemoView(initialMode: AppSettings.surfaceMode) { [weak self] in
                    self?.window?.orderOut(nil)
                }
            }.id(UUID()))
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window?.orderOut(nil)
        return false
    }

    /// Compatibility with the dormant upstream approval callback. This preview
    /// advances only in its own UI and never produces an intervention.
    func completeIfNeeded(sessionId _: String, intervention _: SessionIntervention) {}
}

private struct MacIslandMonitorDemoView: View {
    @State private var demo = MacIslandMonitorDemo()
    @State private var mode: IslandSurfaceMode
    let onClose: () -> Void

    init(initialMode: IslandSurfaceMode, onClose: @escaping () -> Void) {
        _mode = State(initialValue: initialMode)
        self.onClose = onClose
    }

    private var title: String {
        switch demo.stage {
        case .working: "正在处理"
        case .attention: "需要关注"
        case .complete: "任务已完成"
        }
    }

    private var explanation: String {
        switch demo.stage {
        case .working: "任务开始后，Island 的状态会更新。悬停或点击可查看本机进度，详情不会自动弹出。"
        case .attention: "需要你处理时，Island 会保留提示。使用真实会话的打开按钮返回原客户端，在那里回复或审批。"
        case .complete: "完成后，Island 会显示结果状态。顶部与悬浮形态使用同一套观察规则，始终保持静音。"
        }
    }

    private var symbol: String {
        switch demo.stage {
        case .working: "ellipsis"
        case .attention: "exclamationmark.bubble"
        case .complete: "checkmark"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(appLocalized: "Mac Island 监控演示").font(.title2.weight(.semibold))
                Spacer()
                Text(appLocalized: "演示数据").font(.caption.weight(.medium))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            Text(appLocalized: "这是独立预览，不会操作任何客户端，也不会进入当前会话或最近记录。")
                .font(.callout).foregroundStyle(.secondary)
            Picker(AppLocalization.string("展示位置"), selection: $mode) {
                Text(appLocalized: "屏幕顶部").tag(IslandSurfaceMode.notch)
                Text(appLocalized: "悬浮 Island").tag(IslandSurfaceMode.floatingPet)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("monitor-demo.mode")

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: symbol).font(.title3.weight(.semibold))
                    Text(appLocalized: title).font(.headline)
                    Spacer()
                    Text("\(demo.stage.rawValue + 1) / 3").font(.caption).monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 18)
                .frame(width: mode == .notch ? 350 : 280)
                .background(Color.black, in: RoundedRectangle(cornerRadius: mode == .notch ? 18 : 30))
                .frame(maxWidth: .infinity, alignment: mode == .notch ? .center : .trailing)
                .padding(.top, mode == .notch ? 0 : 22)
                Text(appLocalized: explanation).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("monitor-demo.stage")

            Spacer(minLength: 0)
            HStack {
                Button(AppLocalization.string("关闭演示"), action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if demo.stage == .complete {
                    Button(AppLocalization.string("mac-island.action.done"), action: onClose)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(AppLocalization.string("下一步")) { demo.advance() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("monitor-demo.next")
                }
            }
        }
        .padding(28)
        .frame(width: 640, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
