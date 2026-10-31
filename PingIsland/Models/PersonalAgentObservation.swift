import Foundation

nonisolated enum PersonalAgentClient: String, CaseIterable, Identifiable, Sendable {
    case muse, grokBot, dot

    var id: String { rawValue }
    var name: String {
        switch self {
        case .muse: "Muse"
        case .grokBot: "Grok Bot"
        case .dot: "Dot"
        }
    }
    var bundleID: String {
        switch self {
        case .muse: "com.meta.endo"
        case .grokBot: "com.anysphere.sand"
        case .dot: "com.openai.codex"
        }
    }
    // A new client version needs its own metadata contract, not a best-effort
    // scan of arbitrary UI. Dot has no independently verified task source.
    var supportedVersions: Set<String> {
        switch self {
        case .muse: ["4.1", "6.0"]
        case .grokBot: ["0.68.1"]
        case .dot: []
        }
    }
    var canObserve: Bool {
        MacIslandProductPolicy.personalAgentInterfaceClients.contains(self) && !supportedVersions.isEmpty
    }
}

nonisolated enum PersonalAgentHealthPhase: String, Sendable {
    case disabled, paused, sleeping, permissionRequired, appNotRunning
    case unsupportedVersion, sourceUnavailable, observing, interfaceUnavailable, readFailed, budgetExceeded

    var localizationKey: String { "personal-agent.health.\(rawValue)" }
}

nonisolated struct PersonalAgentHealth: Equatable, Sendable {
    var phase: PersonalAgentHealthPhase
    var lastSuccessfulRead: Date?
    var version: String?
}

/// UI observations deliberately have no persistence conformance. The view ID
/// identifies one Bot context in a snapshot, never a native Bot/task ID,
/// routing target or history. Activities belong to that card, not to sessions.
nonisolated struct PersonalAgentObservation: Identifiable, Equatable, Sendable {
    enum Scope: String, Sendable {
        case visibleConversation, visibleActivity
        var localizationKey: String { "personal-agent.scope.\(rawValue)" }
    }

    let id: String
    let client: PersonalAgentClient
    let agentName: String?
    let nativeTaskTitle: String?
    let nativeActivityLabels: [String]
    let scope: Scope
    let observedAt: Date

    // The current desktop contracts expose neither field independently.
    var nativeTaskID: String? { nil }
    var lastActivity: Date? { nil }
    var statusLocalizationKey: String { "personal-agent.status.unknown" }
    var countsAsRunning: Bool { false }
    var canNavigateToTask: Bool { false }
}

nonisolated struct PersonalAgentApplication: Equatable, Sendable {
    let client: PersonalAgentClient
    let processID: Int32
    let bundleID: String
    let version: String
}

/// A bounded, transient metadata projection, including in synthetic fixtures.
/// Text entries and conversation subtrees never enter this structure.
nonisolated struct PersonalAgentAXNode: Equatable, Sendable {
    let role: String
    var label: String = ""
    var selected: Bool = false
    var children: [PersonalAgentAXNode] = []
}

nonisolated struct PersonalAgentReadResult: Sendable {
    enum Outcome: Sendable { case success, permissionRequired, failed, budgetExceeded }
    let outcome: Outcome
    var windows: [PersonalAgentAXNode] = []
}

nonisolated enum PersonalAgentAdapter {
    static func observations(
        client: PersonalAgentClient, version: String, windows: [PersonalAgentAXNode], observedAt: Date, epoch: UInt64
    ) -> [PersonalAgentObservation] {
        guard client.canObserve, client.supportedVersions.contains(version) else { return [] }
        var result: [PersonalAgentObservation] = []
        for window in windows {
            switch client {
            case .grokBot:
                for details in metadataNodes(window)
                where details.role == "AXButton" && details.label == "View conversation details" {
                    let name = metadataNodes(details).first { $0.role == "AXStaticText" && !$0.label.isEmpty }?.label
                    result.append(
                        .init(
                            id: "interface:grokBot:\(epoch):\(result.count)", client: client,
                            agentName: name, nativeTaskTitle: nil, nativeActivityLabels: [],
                            scope: .visibleConversation, observedAt: observedAt))
                }
            case .muse:
                if version == "6.0" {
                    for name in muse60BotContexts(window) {
                        result.append(
                            .init(
                                id: "interface:muse:\(epoch):\(result.count)", client: client,
                                agentName: name, nativeTaskTitle: nil, nativeActivityLabels: [],
                                scope: .visibleConversation, observedAt: observedAt))
                    }
                    continue
                }
                for panel in museBotPanels(window) {
                    let nameRange = museIdentityTextRange(in: panel.children.map { Optional($0) })
                    let name = nameRange.flatMap { range in
                        let identity = panel.children[range]
                        let texts = identity.flatMap { $0.role == "AXGroup" ? $0.children.map(\.label) : [$0.label] }
                        return museAgentName(from: texts)
                    }
                    let activitySelected = panel.children.contains { $0.label == "Activity" && $0.selected }
                    var labels: [String] = []
                    var inActivity = false
                    if activitySelected {
                        for node in metadataNodes(panel) {
                            if node.role == "AXHeading" { inActivity = isActivityDateHeading(node.label) }
                            if inActivity, node.role == "AXButton", isNativeActivityLabel(node.label) {
                                // Preserve combined labels and duplicates in source order.
                                // Never split them into inferred titles/status/timestamps.
                                labels.append(node.label)
                            }
                        }
                    }
                    guard name != nil || !labels.isEmpty else { continue }
                    result.append(
                        .init(
                            id: "interface:muse:\(epoch):\(result.count)", client: client,
                            agentName: name, nativeTaskTitle: nil, nativeActivityLabels: labels,
                            scope: activitySelected ? .visibleActivity : .visibleConversation, observedAt: observedAt))
                }
            case .dot: break
            }
        }
        return result
    }

    /// Muse 6.0 renders two mirrored avatar controls for one current Bot.
    /// Verify the adjacent composer/avatar controls and the native navigation
    /// rail before admitting their names. Side-chat titles are never Bot names.
    private static func muse60BotContexts(_ root: PersonalAgentAXNode) -> [String?] {
        guard !isPrivateSubtree(role: root.role, label: root.label) else { return [] }
        if root.role == "AXGroup", let rail = root.children.first,
            rail.role == "AXGroup",
            rail.children.contains(where: { $0.role == "AXLink" && isMuse60ChatLink($0.label) }),
            rail.children.contains(where: { $0.role == "AXButton" && $0.label == "Search" }),
            rail.children.contains(where: { $0.role == "AXPopUpButton" && $0.label == "Settings" }),
            root.children.count >= 4
        {
            for index in 1..<(root.children.count - 2) {
                let composer = root.children[index]
                let first = root.children[index + 1]
                let second = root.children[index + 2]
                guard composer.role == "AXButton", composer.label == muse60ComposerLabel,
                    composer.children.isEmpty,
                    first.role == "AXButton", second.role == "AXButton",
                    first.children.isEmpty, second.children.isEmpty,
                    !first.label.isEmpty, first.label == second.label,
                    !isPrivateSubtree(role: first.role, label: first.label)
                else { continue }
                let suffix = ", needs approval"
                let name = (first.label.hasSuffix(suffix) ? String(first.label.dropLast(suffix.count)) : first.label)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // The source's default avatar label is not a native Bot name.
                return [name.isEmpty || name == "Agent avatar" ? nil : name]
            }
        }
        return root.children.flatMap(muse60BotContexts)
    }

    static let muse60ComposerLabel = "Message Attach file Dictate a message Send"

    private static func isMuse60ChatLink(_ label: String) -> Bool {
        label == "Chat" || label.range(of: "^Chat, [1-9][0-9]* notifications?$", options: .regularExpression) != nil
    }

    static func metadataNodes(_ root: PersonalAgentAXNode) -> [PersonalAgentAXNode] {
        guard !isPrivateSubtree(role: root.role, label: root.label) else { return [] }
        return [root] + root.children.flatMap(metadataNodes)
    }

    private static func museBotPanels(_ root: PersonalAgentAXNode) -> [PersonalAgentAXNode] {
        guard !isPrivateSubtree(role: root.role, label: root.label) else { return [] }
        let nested = root.children.flatMap(museBotPanels)
        if !nested.isEmpty { return nested }
        // The native panel exposes these controls as direct siblings. Do not
        // aggregate unrelated panes/windows or merge Bots by their names.
        guard
            ["Activity", "Approvals", "Upcoming", "Identity"].allSatisfy({ label in
                root.children.contains { isMuseTab($0, label: label) }
            })
        else { return [] }
        return [root]
    }

    /// Only this exact Muse 4.1 sibling header admits otherwise skipped text.
    /// Accept the native one-level wrappers or adjacent name/badge text leaves.
    /// Nil slots are used before reading values in the AX reader.
    static func museIdentityTextRange(in children: [PersonalAgentAXNode?]) -> Range<Int>? {
        guard children.count >= 7 else { return nil }
        for index in 2...(children.count - 5) {
            guard children[index - 2]?.role == "AXImage", children[index - 2]?.label == "Muse avatar",
                children[index - 1].map(isMuseNameControl) == true
            else { continue }
            let tabs = ["Activity", "Approvals", "Upcoming", "Identity"]
            for count in 1...2 {
                let end = index + count
                guard end + tabs.count <= children.count,
                    (index..<end).allSatisfy({
                        children[$0] == nil || children[$0]?.role == "AXStaticText"
                            || (count == 1 && children[$0].map(isMuseIdentityGroup) == true)
                    })
                else { continue }
                if tabs.enumerated().allSatisfy({ offset, label in
                    children[end + offset].map { isMuseTab($0, label: label) } == true
                }) {
                    return index..<end
                }
            }
        }
        return nil
    }

    private static func isMuseNameControl(_ node: PersonalAgentAXNode) -> Bool {
        if node.role == "AXGroup", node.children.count == 1,
            !isPrivateSubtree(role: node.role, label: node.label)
        {
            let control = node.children[0]
            return ["AXPopUpButton", "AXMenuButton", "AXButton"].contains(control.role)
                && control.label == "Edit avatar and name"
        }
        return ["AXPopUpButton", "AXMenuButton", "AXButton"].contains(node.role)
            && node.label == "Edit avatar and name"
    }

    private static func isMuseIdentityGroup(_ node: PersonalAgentAXNode) -> Bool {
        node.role == "AXGroup" && !isPrivateSubtree(role: node.role, label: node.label)
            && node.children.count <= 2 && node.children.allSatisfy { $0.role == "AXStaticText" }
    }

    private static func isMuseTab(_ node: PersonalAgentAXNode, label: String) -> Bool {
        ["AXCheckBox", "AXRadioButton", "AXButton"].contains(node.role) && node.label == label
    }

    private static func museAgentName(from texts: [String]) -> String? {
        // The verified header combines the native name with a connection badge.
        // Remove only that exact trailing UI badge, not words from activities.
        let name: String
        if texts.count == 2, texts[1] == "Connected" {
            name = texts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        } else if texts.count == 1, texts[0].hasSuffix(" Connected") {
            name = String(texts[0].dropLast(" Connected".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return nil
        }
        return name.isEmpty ? nil : name
    }

    static func isPrivateSubtree(role: String, label: String) -> Bool {
        if ["AXTextArea", "AXTextField", "AXSearchField"].contains(role) { return true }
        return ["conversation transcript", "chat messages", "bot list", "prompt"]
            .contains(label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func isActivityDateHeading(_ label: String) -> Bool {
        ["Today", "Yesterday"].contains(label)
            || label.range(
                of: "^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [0-9]{1,2}$",
                options: .regularExpression) != nil
    }

    private static func isNativeActivityLabel(_ label: String) -> Bool {
        // Verified Muse 4.1 Activity rows end with a native 12-hour time label.
        label.range(of: "\\b[0-9]{1,2}:[0-9]{2} ?[ap]m$", options: [.regularExpression, .caseInsensitive]) != nil
    }
}
