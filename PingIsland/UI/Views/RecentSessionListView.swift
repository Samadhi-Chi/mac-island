import SwiftUI

struct RecentSessionListView: View {
    @ObservedObject var index: RecentSessionIndex
    let currentSessions: [SessionState]
    @ObservedObject var titles: SessionListTitleStore
    let observedSession: (RecentSessionRecord) -> SessionState?
    @Binding var selectedRecordID: String?
    let onOpen: (RecentSessionRecord) -> Void

    private var records: [RecentSessionRecord] {
        SessionListPresentation.history(records: index.records, currentSessions: currentSessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if records.isEmpty {
                Text(appLocalized: emptyMessageKey)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 18)
                    .accessibilityIdentifier("recent-session-empty")
            } else {
                Text("这里显示当前列表以外、曾在本机观察到的会话。")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(records) { record in
                                RecentSessionRow(
                                    record: record,
                                    session: observedSession(record) ?? record.navigationSession,
                                    title: titles.title(for: record, observedSession: observedSession(record)),
                                    isSelected: selectedRecordID == record.id,
                                    onSelect: { selectedRecordID = record.id },
                                    onOpen: {
                                        selectedRecordID = record.id
                                        onOpen(record)
                                    }
                                )
                                .id(record.id)
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: selectedRecordID) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                .frame(height: 260)
            }
            if let message = index.storageMessage {
                Text(appLocalized: message)
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            Text("仅保存本机路由信息，不保存对话正文。")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: OpenedPanelContentHeightPreferenceKey.self, value: geometry.size.height)
            }
        }
    }

    private var emptyMessageKey: String {
        if index.retention == .disabled { return "最近会话记录已关闭，可在设置中开启。" }
        return index.records.isEmpty
            ? "暂无最近记录；新的本机会话活动会显示在这里。"
            : "最近活动都在当前会话中，可返回当前会话查看。"
    }
}

private struct RecentSessionRow: View {
    let record: RecentSessionRecord
    let session: SessionState
    let title: SessionListTitle
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    @State private var showsMetadata = false
    @ObservedObject private var actions = SessionActionController.shared
    @ObservedObject private var privacy = ScreenPrivacyStore.shared

    var body: some View {
        if !privacy.effectiveMode.showsDetails {
            VStack(spacing: 6) {
                ScreenPrivacySessionRow(
                    presentation: ScreenSessionPresentation(record: record, title: title, mode: privacy.effectiveMode),
                    showsTitles: privacy.effectiveMode.showsTitles,
                    selected: isSelected, navigationEnabled: record.origin != "unknown",
                    onSelect: onSelect, onOpen: onOpen
                )
                if let feedback = actions.feedback, feedback.matches(record) {
                    SessionActionFeedbackView(
                        feedback: feedback, onDismiss: actions.dismissFeedback,
                        showsClientName: false)
                }
            }
        } else {
            detailedBody
        }
    }

    private var detailedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    if let name = title.nativeName {
                        Text(verbatim: String(name.prefix(512))).fontWeight(.semibold)
                            .lineLimit(1)
                    } else {
                        Text("标题暂不可用").fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    HStack(spacing: 4) {
                        Text("目录").foregroundStyle(.white.opacity(0.45))
                        Text(verbatim: URL(fileURLWithPath: record.workspace).lastPathComponent)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
                    HStack(spacing: 5) {
                        Text(verbatim: record.clientName)
                        Text("·")
                        Text(record.lastActivity, format: .dateTime.month().day().hour().minute())
                        if record.origin == "unknown" { Text("来源待确认") }
                    }
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 7) {
                    Menu {
                        Button("会话详情…") { showsMetadata = true }
                        Divider()
                        SessionQuickActionsMenuContent(session: session, navigationEnabled: record.origin != "unknown")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel(Text("会话详情和快捷操作"))
                    .popover(isPresented: $showsMetadata) {
                        SessionListMetadataView(record: record, title: title)
                    }
                    if record.origin != "unknown" {
                        Button(action: onOpen) {
                            Text(verbatim: AppLocalization.format("在 %@ 打开", record.clientName))
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.blue)
                        .disabled(actions.activeSessionIDs.contains(session.sessionId))
                        .accessibilityIdentifier("recent-session-open")
                    }
                }
            }
            if let feedback = actions.feedback, feedback.matches(record) {
                SessionActionFeedbackView(
                    feedback: feedback, onDismiss: actions.dismissFeedback,
                    showsClientName: false)
            }
        }
        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.9))
        .padding(10)
        .background(.white.opacity(isSelected ? 0.15 : 0.05), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recent-session-row")
    }
}
