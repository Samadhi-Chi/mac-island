import SwiftUI

/// Shared by docked and detached content, including list, hover and chat routes.
struct SessionActionFeedbackView: View {
    let feedback: SessionActionController.Feedback
    let onDismiss: () -> Void
    var showsClientName = true
    @ObservedObject private var privacy = ScreenPrivacyStore.shared

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: feedback.result == nil ? "arrow.up.forward.app" : "info.circle")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if showsClientName && privacy.effectiveMode.showsDetails {
                    Text(verbatim: feedback.clientName)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                Text(appLocalized: messageKey)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("关闭操作反馈"))
            .accessibilityIdentifier("session-action-feedback-dismiss")
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.9))
        .padding(10)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session-action-feedback")
    }

    private var messageKey: String {
        switch feedback.result {
        case nil: "正在定位目标…"
        case .targetConfirmed: "已定位目标终端。"
        case .requestSent(.sessionLink): "已发送会话打开请求；尚未确认会话已显示。"
        case .requestSent(.terminal): "已请求定位终端；尚未确认目标会话。"
        case .requestSent(.workspace): "已请求打开项目窗口；尚未确认目标会话。"
        case .requestSent(.tmux): "已发送 tmux 切换请求；尚未确认前台目标。"
        case .applicationOpened: "已打开应用；未确认目标会话，请在客户端中选择。"
        case .completed(.copiedSessionID): "已复制原生会话 ID。"
        case .completed(.hiddenLocally): "已从当前列表隐藏；有新活动时会重新显示。"
        case .unavailable(.invalidWorkspace), .failed(.invalidWorkspace): "项目目录不存在或不属于本机。"
        case .unavailable(.clipboardUnavailable), .failed(.clipboardUnavailable): "无法复制到剪贴板，请重试。"
        case .unavailable(.navigationSuppressed), .failed(.navigationSuppressed):
            "当前会话没有可用的导航目标。"
        case .unavailable(.targetNotFound), .failed(.targetNotFound):
            "无法打开目标。请检查客户端是否可用及终端自动化权限后重试。"
        }
    }
}
