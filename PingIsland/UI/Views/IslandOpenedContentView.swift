import SwiftUI

private struct SessionActionFeedbackHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ScreenPrivacyHeaderHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct IslandOpenedContentView: View {
    @ObservedObject var sessionMonitor: SessionMonitor
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var actions = SessionActionController.shared
    @State private var feedbackHeight: CGFloat = 0
    @State private var privacyHeaderHeight: CGFloat = 0
    @ObservedObject private var listPresentation = SessionListPresentationState.shared
    @ObservedObject private var privacy = ScreenPrivacyStore.shared
    let surface: IslandExpandedSurface
    let trigger: IslandExpandedTrigger
    let style: IslandOpenedPresentationStyle
    let activeCompletionNotification: SessionCompletionNotification?
    var highlightedSessionStableID: String? = nil
    var contentWidthOverride: CGFloat? = nil
    let onAttentionActionCompleted: () -> Void
    let onCompletionNotificationHoverChanged: (Bool) -> Void
    let onDismissCompletionNotification: () -> Void
    var onRecentSessionsRequested: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(
                    appLocalized: privacy.isTemporarilyHidden
                        ? "screen-privacy.hidden" : privacy.mode.localizationKey
                )
                .foregroundStyle(.white.opacity(0.5))
                Spacer()
                ScreenPrivacyToggleButton()
            }
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.75))
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ScreenPrivacyHeaderHeightPreferenceKey.self, value: geometry.size.height)
                }
            }
            if route != .sessionList {
                VStack(spacing: 8) {
                    if let feedback = actions.feedback {
                        SessionActionFeedbackView(feedback: feedback, onDismiss: actions.dismissFeedback)
                    }
                    if route != .sessionList {
                        HStack {
                            Button("最近记录", systemImage: "clock") {
                                onRecentSessionsRequested()
                                listPresentation.section = .recent
                                viewModel.presentSessionList(reason: .click)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            if let session = actionContextSession {
                                Menu("会话快捷操作", systemImage: "ellipsis.circle") {
                                    SessionQuickActionsMenuContent(session: session) {
                                        SessionActionController.shared.hideLocally(
                                            session, using: sessionMonitor.hideSessionLocally)
                                        viewModel.exitChat()
                                    }
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .layoutPriority(1)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: SessionActionFeedbackHeightPreferenceKey.self, value: geometry.size.height)
                    }
                }
            }
            routeContent
        }
        .frame(width: contentWidth)
        .onPreferenceChange(SessionActionFeedbackHeightPreferenceKey.self) { feedbackHeight = $0 }
        .onPreferenceChange(ScreenPrivacyHeaderHeightPreferenceKey.self) { privacyHeaderHeight = $0 }
        .transformPreference(OpenedPanelContentHeightPreferenceKey.self) { height in
            // Keep measuring intrinsic list/notification content, not the outer
            // ScrollView whose available height is itself driven by this value.
            if height > 0 {
                height += privacyHeaderHeight + 8
                if route != .sessionList { height += feedbackHeight + 8 }
            }
        }
        .transaction { if !privacy.effectiveMode.showsDetails { $0.disablesAnimations = true } }
        .onAppear {
            sessionMonitor.refreshUsageState()
        }
    }

    private var route: IslandExpandedRoute {
        if listPresentation.section == .recent, case .instances = viewModel.contentType { return .sessionList }
        return IslandExpandedRouteResolver.resolve(
            surface: surface,
            trigger: trigger,
            contentType: viewModel.contentType,
            sessions: sessionMonitor.instances,
            activeCompletionNotification: activeCompletionNotification,
            hasPersonalAgentObservations: !sessionMonitor.personalAgentObservations.isEmpty
                || sessionMonitor.hasEnabledPersonalAgentSources,
            contentVisibility: privacy.effectiveMode
        )
    }

    private var hoverPreviewSessions: [SessionState] {
        IslandExpandedRouteResolver.activePreviewSessions(from: sessionMonitor.instances)
    }

    private var actionContextSession: SessionState? {
        switch route {
        case .chat(let session), .attentionNotification(let session): liveSession(for: session)
        case .completionNotification(let notification): liveSession(for: notification.session)
        case .sessionList, .hoverDashboard: nil
        }
    }

    @ViewBuilder
    private var routeContent: some View {
        switch route {
        case .sessionList:
            SessionListView(
                sessionMonitor: sessionMonitor,
                viewModel: viewModel,
                enableKeyboardNavigation: true,
                highlightedSessionStableID: highlightedSessionStableID
            )
        case .hoverDashboard:
            SessionHoverDashboardView(
                sessions: hoverPreviewSessions,
                sessionMonitor: sessionMonitor,
                density: surface == .floating ? .detachedCompact : .regular,
                onQuestionInteractionStateChanged: { viewModel.setInlineTextInputActive($0) }
            )
        case .attentionNotification(let session):
            SessionAttentionNotificationView(
                session: liveSession(for: session),
                sessionMonitor: sessionMonitor,
                density: surface == .floating ? .detachedCompact : .regular,
                suppressInAppPromptControls: settings.effectiveRoutePromptsToTerminal,
                onQuestionInteractionStateChanged: { viewModel.setInlineTextInputActive($0) },
                onActionCompleted: onAttentionActionCompleted
            )
        case .completionNotification(let notification):
            SessionCompletionNotificationView(
                notification: liveNotification(notification),
                presentationStyle: style == .detached ? .bubble : .panel,
                onHoverChanged: onCompletionNotificationHoverChanged,
                onDismiss: onDismissCompletionNotification
            )
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: OpenedPanelContentHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            )
        case .chat(let session):
            let liveSession = liveSession(for: session)

            if liveSession.provider == .claude || liveSession.provider == .kimi {
                ChatView(
                    sessionId: liveSession.sessionId,
                    initialSession: liveSession,
                    sessionMonitor: sessionMonitor,
                    viewModel: viewModel
                )
            } else {
                CodexSessionView(
                    session: liveSession,
                    sessionMonitor: sessionMonitor,
                    viewModel: viewModel
                )
            }
        }
    }

    private func liveSession(for session: SessionState) -> SessionState {
        sessionMonitor.instances.first(where: { $0.sessionId == session.sessionId }) ?? session
    }

    private func liveNotification(_ notification: SessionCompletionNotification) -> SessionCompletionNotification {
        guard
            let latestSession = sessionMonitor.instances.first(where: {
                $0.sessionId == notification.session.sessionId
            })
        else {
            return notification
        }

        var updated = notification
        updated.session = latestSession
        return updated
    }

    private var contentWidth: CGFloat {
        if let contentWidthOverride {
            return contentWidthOverride
        }

        switch style {
        case .docked:
            return viewModel.openedSize.width - 24
        case .detached:
            return viewModel.detachedSize.width - 24
        }
    }
}
