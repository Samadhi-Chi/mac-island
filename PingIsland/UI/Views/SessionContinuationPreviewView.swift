import AppKit
import SwiftUI

/// Embed only after an explicit preview action; creating this view never starts a client.
struct SessionContinuationPreviewView: View {
    let session: SessionState
    var onClose: () -> Void
    @State private var preview: SessionContinuationPreview?
    @State private var messageKey: String?
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var hasSubmitted = false
    @ObservedObject private var privacy = ScreenPrivacyStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(appLocalized: "续接预览").font(.headline)
                    if !privacy.effectiveMode.showsDetails {
                        Text(appLocalized: "screen-privacy.details-hidden").foregroundStyle(.secondary)
                    } else if isLoading {
                        ProgressView("正在检查客户端与工作目录…")
                    } else if let preview {
                        LabeledContent("客户端", value: preview.target.client.displayName)
                        LabeledContent("版本", value: preview.clientVersion)
                        LabeledContent("会话 ID", value: preview.target.nativeSessionID)
                            .textSelection(.enabled)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appLocalized: "工作目录").foregroundStyle(.secondary)
                            Text(preview.target.workingDirectory).textSelection(.enabled)
                        }
                        ScrollView {
                            Text(preview.command.shellCommand)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 90)
                        if !preview.executionCertified {
                            Text(appLocalized: SessionContinuationError.notCertified.messageKey)
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Text(appLocalized: "目标：Terminal.app 新窗口。不会附加消息或修改客户端的审批设置。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("复制命令") {
                                NSPasteboard.general.clearContents()
                                let copied = NSPasteboard.general.setString(
                                    preview.command.shellCommand, forType: .string)
                                messageKey = copied ? "命令已复制；复制不会启动会话。" : "无法写入剪贴板，请重试。"
                            }
                            .accessibilityIdentifier("continuation.copy")
                            Spacer()
                            Button(AppLocalization.string(isSubmitting ? "正在请求…" : "确认并在 Terminal 中续接")) {
                                isSubmitting = true
                                Task {
                                    let result = await SessionContinuationService.shared.confirm(previewID: preview.id)
                                    messageKey = result.messageKey
                                    isSubmitting = false
                                    switch result {
                                    case .requestSubmitted, .deliveryUncertain: hasSubmitted = true
                                    case .unavailable: break
                                    }
                                }
                            }
                            .disabled(!preview.executionCertified || isSubmitting || hasSubmitted)
                            .accessibilityIdentifier("continuation.confirm")
                        }
                    }
                    if privacy.effectiveMode.showsDetails, let messageKey {
                        Text(appLocalized: messageKey).font(.callout).accessibilityIdentifier("continuation.feedback")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("关闭", action: onClose).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 400, idealWidth: 500, maxWidth: 600)
        .task(id: session.sessionId) {
            isLoading = true
            switch await SessionContinuationService.shared.prepare(session: session) {
            case .success(let value): preview = value
            case .failure(let error): messageKey = error.messageKey
            }
            isLoading = false
        }
        .onDisappear {
            SessionContinuationService.shared.cancelPreparation(sessionKey: session.sessionId)
            if let preview { SessionContinuationService.shared.cancel(previewID: preview.id) }
        }
    }
}
