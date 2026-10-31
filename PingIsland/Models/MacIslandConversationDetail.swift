import Foundation

/// Rich local-only projection used by the expanded Mac Island card.
///
/// This type is intentionally not Codable. It is rebuilt from SessionState in
/// memory and never enters caches, diagnostics, Bridge logs, or telemetry.
struct MacIslandConversationDetail: Equatable, Sendable {
    struct Activity: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case thinking
            case runningTool
            case completedTool
            case failedTool
            case waitingTool
            case interrupted
        }

        let kind: Kind
        let text: String
    }

    let userText: String?
    let assistantText: String?
    let activities: [Activity]

    /// Latest activity retained for compact surfaces and existing call sites.
    var activity: Activity? { activities.last }
}

enum MacIslandConversationDetailBuilder {
    static func make(from session: SessionState) -> MacIslandConversationDetail {
        let latestUserIndex = session.chatItems.lastIndex { item in
            if case .user = item.type { return true }
            return false
        }
        let latestUserItem = latestUserIndex.map { session.chatItems[$0] }
        let currentTurnItems: ArraySlice<ChatHistoryItem>
        if let latestUserIndex {
            currentTurnItems = session.chatItems.suffix(from: latestUserIndex + 1)
        } else {
            currentTurnItems = session.chatItems[...]
        }

        let userText: String? = {
            if let latestUserItem, case .user(let text) = latestUserItem.type {
                return bounded(text)
            }
            return bounded(session.firstUserMessage)
        }()

        let assistantText: String? = {
            for item in currentTurnItems.reversed() {
                if case .assistant(let text) = item.type {
                    return bounded(text)
                }
            }

            if latestUserIndex == nil, session.lastMessageRole == "assistant" {
                return bounded(session.lastMessage)
            }
            return nil
        }()

        let activities = recentActivities(
            in: currentTurnItems,
            phase: session.phase
        )

        return MacIslandConversationDetail(
            userText: userText,
            assistantText: assistantText,
            activities: activities
        )
    }

    private static func recentActivities(
        in items: ArraySlice<ChatHistoryItem>,
        phase: SessionPhase
    ) -> [MacIslandConversationDetail.Activity] {
        var newestFirst: [MacIslandConversationDetail.Activity] = []
        for item in items.reversed() {
            let activity: MacIslandConversationDetail.Activity?
            switch item.type {
            case .thinking(let text):
                activity = boundedActivity(text).map {
                    .init(kind: .thinking, text: $0)
                }

            case .toolCall(let tool):
                let name = friendlyToolName(tool.name)
                let preview = SessionTextSanitizer.sanitizedDisplayText(tool.inputPreview)
                let statusText = SessionTextSanitizer.sanitizedDisplayText(tool.statusDisplay.text)
                let detail = preview ?? statusText
                let text = detail.map { "\(name) · \($0)" } ?? name
                activity = .init(
                    kind: activityKind(for: tool.status),
                    text: boundedActivity(text) ?? name
                )

            case .interrupted:
                activity = .init(kind: .interrupted, text: "已中断")

            case .user, .assistant:
                activity = nil
            }

            guard let activity else { continue }
            newestFirst.append(activity)
            if newestFirst.count == 5 { break }
        }

        // Display a small timeline from older to newer while keeping `activity`
        // as the latest element for compact previews.
        return newestFirst.reversed()
    }

    private static func activityKind(
        for status: ToolStatus
    ) -> MacIslandConversationDetail.Activity.Kind {
        switch status {
        case .running: .runningTool
        case .waitingForApproval: .waitingTool
        case .success: .completedTool
        case .error: .failedTool
        case .interrupted: .interrupted
        }
    }

    private static func friendlyToolName(_ rawName: String) -> String {
        let formatted = MCPToolFormatter.formatToolName(rawName)
        guard formatted == rawName else { return formatted }

        return
            rawName
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .split(separator: "_")
            .map { word in
                guard let first = word.first else { return String(word) }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func bounded(_ text: String?) -> String? {
        SessionTextSanitizer.boundedMultilineDisplayText(
            text,
            maxCharacters: MacIslandPresentationPolicy.conversationDetailCharacterLimit,
            truncationNotice: AppLocalization.string(SessionDetailDisplayStrings.truncationNoticeKey)
        )
    }

    private static func boundedActivity(_ text: String?) -> String? {
        guard let text = SessionTextSanitizer.sanitizedDisplayText(text) else { return nil }
        let limit = MacIslandPresentationPolicy.conversationActivityCharacterLimit
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }
}
