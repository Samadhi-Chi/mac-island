import SwiftUI

struct SessionQuickActionsMenuContent: View {
    let session: SessionState
    var navigationEnabled = true
    var onHide: (() -> Void)? = nil

    var body: some View {
        Button("返回目标会话", systemImage: "arrow.up.forward.app") {
            Task { await SessionActionController.shared.perform(session) }
        }
        .disabled(!navigationEnabled || session.clientInfo.suppressesActivationNavigation)
        Button("打开项目目录", systemImage: "folder") {
            SessionActionController.shared.openProject(session)
        }
        .disabled(session.isRemoteSession)
        Button("复制会话 ID", systemImage: "doc.on.doc") {
            SessionActionController.shared.copyNativeSessionID(session)
        }
        if (try? SessionContinuationTarget.make(from: session)) != nil {
            Button("续接预览", systemImage: "arrow.clockwise") {
                SessionContinuationWindowController.shared.present(session)
            }
        }
        if let onHide {
            Divider()
            Button("从当前列表隐藏", systemImage: "eye.slash", action: onHide)
        }
    }
}
