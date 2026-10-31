import ApplicationServices
import Foundation

nonisolated protocol PersonalAgentReading: Sendable {
    func read(_ application: PersonalAgentApplication) async -> PersonalAgentReadResult
}

/// All potentially blocking AX reads run on this actor, never the main actor.
/// It has no API for AX actions, writing values, launching apps or UI clicks.
actor PersonalAgentAccessibilityReader: PersonalAgentReading {
    func read(_ application: PersonalAgentApplication) async -> PersonalAgentReadResult {
        guard SessionMonitor.allowsLiveMonitoring(), application.client.canObserve,
            application.bundleID == application.client.bundleID,
            application.client.supportedVersions.contains(application.version)
        else {
            return .init(outcome: .failed)
        }
        guard AXIsProcessTrusted() else { return .init(outcome: .permissionRequired) }
        let root = AXUIElementCreateApplication(application.processID)
        AXUIElementSetMessagingTimeout(root, 0.05)
        var budget = Budget()
        let windows = elements(root, attribute: kAXWindowsAttribute, limit: 3, budget: &budget)
        var projected: [PersonalAgentAXNode] = []
        for window in windows {
            if let node = project(
                window, client: application.client, version: application.version,
                depth: 0, allowsText: false, budget: &budget)
            {
                projected.append(node)
            }
        }
        if !AXIsProcessTrusted() { return .init(outcome: .permissionRequired) }
        if budget.exhausted { return .init(outcome: .budgetExceeded) }
        if budget.readFailed || Task.isCancelled { return .init(outcome: .failed) }
        return .init(outcome: .success, windows: projected)
    }

    private struct Budget {
        let deadline = Date().addingTimeInterval(2)
        var nodes = 0
        var exhausted = false
        var readFailed = false

        mutating func allowsRead() -> Bool {
            guard !Task.isCancelled else { return false }
            guard Date() < deadline else {
                exhausted = true
                return false
            }
            return !exhausted
        }
    }

    private func project(
        _ element: AXUIElement, client: PersonalAgentClient, version: String,
        depth: Int, allowsText: Bool, budget: inout Budget
    ) -> PersonalAgentAXNode? {
        guard budget.allowsRead() else { return nil }
        guard depth <= 24, budget.nodes < 400 else {
            budget.exhausted = true
            return nil
        }
        budget.nodes += 1
        AXUIElementSetMessagingTimeout(element, 0.05)
        let role = string(element, attribute: kAXRoleAttribute, budget: &budget)
        // Prune inputs before fetching any values or descendants.
        guard !PersonalAgentAdapter.isPrivateSubtree(role: role, label: "") else { return nil }
        let muse60 = client == .muse && version == "6.0"
        if role == "AXStaticText", muse60 || !allowsText { return nil }
        let description = string(element, attribute: kAXDescriptionAttribute, budget: &budget)
        let title = string(element, attribute: kAXTitleAttribute, budget: &budget)
        var label = description.isEmpty ? title : description
        guard !PersonalAgentAdapter.isPrivateSubtree(role: role, label: label) else { return nil }
        if muse60, role == "AXButton", label == PersonalAgentAdapter.muse60ComposerLabel {
            // A fixed structural anchor only: never inspect the composer.
            return .init(role: role, label: label)
        }
        if !muse60, ["AXStaticText", "AXHeading"].contains(role), label.isEmpty {
            label = string(element, attribute: kAXValueAttribute, budget: &budget)
        }
        let selected =
            ["Activity", "Approvals", "Upcoming", "Identity"].contains(label)
            && (bool(element, attribute: kAXValueAttribute, budget: &budget)
                || bool(element, attribute: kAXSelectedAttribute, budget: &budget))
        let childText = !muse60 && (label == "View conversation details" || role == "AXHeading" || allowsText)
        let childElements = elements(element, attribute: kAXChildrenAttribute, limit: 80, budget: &budget)
        var projectedChildren = childElements.map {
            project($0, client: client, version: version, depth: depth + 1, allowsText: childText, budget: &budget)
        }
        if client == .muse, !muse60, let range = PersonalAgentAdapter.museIdentityTextRange(in: projectedChildren) {
            // Admit text only in this verified sibling header. The native name
            // and badge have a one-level wrapper; validate every leaf role
            // before fetching any text. Never enable text throughout the pane.
            for index in range {
                projectedChildren[index] = projectMuseIdentity(childElements[index], budget: &budget)
            }
        }
        let children = projectedChildren.compactMap { $0 }
        // Some web headings expose their string through a static-text child.
        if role == "AXHeading", label.isEmpty {
            label = children.first(where: { $0.role == "AXStaticText" })?.label ?? ""
        }
        return .init(role: role, label: label, selected: selected, children: children)
    }

    private func projectMuseIdentity(_ element: AXUIElement, budget: inout Budget) -> PersonalAgentAXNode? {
        let role = string(element, attribute: kAXRoleAttribute, budget: &budget)
        let leaves: [AXUIElement]
        if role == "AXGroup" {
            leaves = elements(element, attribute: kAXChildrenAttribute, limit: 2, budget: &budget)
            guard !leaves.isEmpty,
                leaves.allSatisfy({ string($0, attribute: kAXRoleAttribute, budget: &budget) == "AXStaticText" })
            else { return nil }
        } else if role == "AXStaticText" {
            leaves = [element]
        } else {
            return nil
        }
        var texts: [PersonalAgentAXNode] = []
        for leaf in leaves {
            let description = string(leaf, attribute: kAXDescriptionAttribute, budget: &budget)
            let title = string(leaf, attribute: kAXTitleAttribute, budget: &budget)
            var label = description.isEmpty ? title : description
            if label.isEmpty { label = string(leaf, attribute: kAXValueAttribute, budget: &budget) }
            guard !PersonalAgentAdapter.isPrivateSubtree(role: "AXStaticText", label: label) else { return nil }
            texts.append(.init(role: "AXStaticText", label: label))
        }
        return role == "AXGroup" ? .init(role: role, children: texts) : texts.first
    }

    private func string(_ element: AXUIElement, attribute: String, budget: inout Budget) -> String {
        guard budget.allowsRead() else { return "" }
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if error == .cannotComplete || error == .invalidUIElement { budget.readFailed = true }
        let text = value as? String ?? ""
        guard text.count <= 1_024 else {
            budget.exhausted = true
            return ""
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func bool(_ element: AXUIElement, attribute: String, budget: inout Budget) -> Bool {
        guard budget.allowsRead() else { return false }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return false }
        return (value as? NSNumber)?.boolValue == true
    }

    private func elements(_ element: AXUIElement, attribute: String, limit: Int, budget: inout Budget) -> [AXUIElement]
    {
        guard budget.allowsRead() else { return [] }
        var count: CFIndex = 0
        let error = AXUIElementGetAttributeValueCount(element, attribute as CFString, &count)
        if error == .cannotComplete || error == .invalidUIElement { budget.readFailed = true }
        guard error == .success, count > 0 else { return [] }
        guard count <= limit else {
            budget.exhausted = true
            return []
        }
        guard budget.allowsRead() else { return [] }
        var values: CFArray?
        guard AXUIElementCopyAttributeValues(element, attribute as CFString, 0, count, &values) == .success else {
            budget.readFailed = true
            return []
        }
        return values as? [AXUIElement] ?? []
    }
}
