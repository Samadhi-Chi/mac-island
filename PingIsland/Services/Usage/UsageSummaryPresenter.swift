import Foundation

enum UsageSummarySeverity: Equatable {
    case healthy
    case warning
    case critical
}

struct UsageSummaryWindow: Equatable {
    let id: String
    let label: String
    let valueText: String
    let resetText: String?
    let resetsAt: Date?
    let severity: UsageSummarySeverity
    let remainingPercentage: Double

    nonisolated init(
        id: String,
        label: String,
        valueText: String,
        resetText: String?,
        resetsAt: Date? = nil,
        severity: UsageSummarySeverity,
        remainingPercentage: Double
    ) {
        self.id = id
        self.label = label
        self.valueText = valueText
        self.resetText = resetText
        self.resetsAt = resetsAt
        self.severity = severity
        self.remainingPercentage = remainingPercentage
    }
}

struct UsageSummaryProvider: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let windows: [UsageSummaryWindow]

    nonisolated init(
        id: String,
        title: String,
        subtitle: String? = nil,
        windows: [UsageSummaryWindow]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.windows = windows
    }
}

enum UsageSummaryPresenter {
    /// Keeps the compact usage surface aligned with the client that is actually
    /// doing work. If nothing is running, the most recently active supported
    /// session remains selected so the header does not flicker between providers.
    nonisolated static func providersFollowingActiveClient(
        _ providers: [UsageSummaryProvider],
        sessions: [SessionState]
    ) -> [UsageSummaryProvider] {
        guard !providers.isEmpty else { return [] }

        let candidates = sessions.compactMap { session -> (SessionState, String)? in
            guard let providerID = usageProviderID(for: session) else { return nil }
            return (session, providerID)
        }
        let activeCandidates = candidates.filter { $0.0.phase.isActive }
        let attentionCandidates = candidates.filter { $0.0.needsAttention }
        let liveCandidates = candidates.filter { $0.0.phase != .ended }
        let rankedCandidates: [(SessionState, String)]

        if !activeCandidates.isEmpty {
            rankedCandidates = activeCandidates
        } else if !attentionCandidates.isEmpty {
            rankedCandidates = attentionCandidates
        } else if !liveCandidates.isEmpty {
            rankedCandidates = liveCandidates
        } else {
            rankedCandidates = candidates
        }

        if let preferredProviderID =
            rankedCandidates
            .sorted(by: providerCandidateSort)
            .first?
            .1
        {
            // Never show a different provider just because the selected
            // provider's quota snapshot has not loaded yet.
            return providers.filter { $0.id == preferredProviderID }
        }

        if let codex = providers.first(where: { $0.id == "codex" }) {
            return [codex]
        }
        if let cursor = providers.first(where: { $0.id == "cursor" }) {
            return [cursor]
        }
        return providers.first.map { [$0] } ?? []
    }

    private nonisolated static func usageProviderID(for session: SessionState) -> String? {
        if MacIslandProductPolicy.isCursorClient(session.clientInfo) {
            return "cursor"
        }
        if session.provider == .codex {
            return "codex"
        }
        return nil
    }

    private nonisolated static func providerCandidateSort(
        _ lhs: (SessionState, String),
        _ rhs: (SessionState, String)
    ) -> Bool {
        if lhs.0.lastActivity == rhs.0.lastActivity {
            return lhs.0.stableId < rhs.0.stableId
        }
        return lhs.0.lastActivity > rhs.0.lastActivity
    }

    nonisolated static func isSevenDayWindowLabel(_ label: String) -> Bool {
        let normalizedLabel =
            label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedLabel == "7d" || normalizedLabel.hasPrefix("7d ")
    }

    nonisolated static func preferredBatteryWindow(for provider: UsageSummaryProvider) -> UsageSummaryWindow? {
        provider.windows.first { $0.id == "cursor-total" }
            ?? provider.windows.first { window in
                isSevenDayWindowLabel(window.label)
            } ?? provider.windows.last
    }

    nonisolated static func sevenDayWindow(
        forProviderID providerID: String,
        in providers: [UsageSummaryProvider]
    ) -> UsageSummaryWindow? {
        providers
            .first { $0.id == providerID }?
            .windows
            .first { isSevenDayWindowLabel($0.label) }
    }

    nonisolated static func remainingHelpText(
        for provider: UsageSummaryProvider,
        locale: Locale = .current
    ) -> String {
        let lines = provider.windows.map { window in
            let components = [
                window.label,
                remainingValueText(for: window.remainingPercentage, locale: locale),
            ]
            return components.joined(separator: " · ")
        }

        guard !lines.isEmpty else {
            return provider.title
        }

        return ([provider.title] + [provider.subtitle].compactMap { $0 } + lines)
            .joined(separator: "\n")
    }

    nonisolated static func providers(
        claudeSnapshot: ClaudeUsageSnapshot?,
        codexSnapshot: CodexUsageSnapshot?,
        cursorSnapshot: CursorUsageSnapshot? = nil,
        mode: UsageValueMode,
        now: Date = .now,
        locale: Locale = .current
    ) -> [UsageSummaryProvider] {
        var providers: [UsageSummaryProvider] = []

        if let snapshot = claudeSnapshot, snapshot.isEmpty == false {
            var windows: [UsageSummaryWindow] = []
            if let fiveHour = snapshot.fiveHour {
                windows.append(
                    UsageSummaryWindow(
                        id: "claude-5h",
                        label: "5h",
                        valueText: valueText(for: fiveHour.usedPercentage, mode: mode, locale: locale),
                        resetText: resetText(for: fiveHour.resetsAt, now: now, locale: locale),
                        resetsAt: fiveHour.resetsAt,
                        severity: severity(forUsedPercentage: fiveHour.usedPercentage),
                        remainingPercentage: remainingPercentage(forUsedPercentage: fiveHour.usedPercentage)
                    )
                )
            }
            if let sevenDay = snapshot.sevenDay {
                windows.append(
                    UsageSummaryWindow(
                        id: "claude-7d",
                        label: "7d",
                        valueText: valueText(for: sevenDay.usedPercentage, mode: mode, locale: locale),
                        resetText: resetText(for: sevenDay.resetsAt, now: now, locale: locale),
                        resetsAt: sevenDay.resetsAt,
                        severity: severity(forUsedPercentage: sevenDay.usedPercentage),
                        remainingPercentage: remainingPercentage(forUsedPercentage: sevenDay.usedPercentage)
                    )
                )
            }
            if !windows.isEmpty {
                providers.append(
                    UsageSummaryProvider(
                        id: "claude",
                        title: "Claude",
                        windows: windows
                    )
                )
            }
        }

        if let snapshot = codexSnapshot, snapshot.isEmpty == false {
            let windows = snapshot.windows.map { window in
                UsageSummaryWindow(
                    id: "codex-\(window.key)",
                    label: window.label,
                    valueText: valueText(for: window.usedPercentage, mode: mode, locale: locale),
                    resetText: resetText(for: window.resetsAt, now: now, locale: locale),
                    resetsAt: window.resetsAt,
                    severity: severity(forUsedPercentage: window.usedPercentage),
                    remainingPercentage: remainingPercentage(forUsedPercentage: window.usedPercentage)
                )
            }

            if !windows.isEmpty {
                providers.append(
                    UsageSummaryProvider(
                        id: "codex",
                        title: "Codex",
                        windows: windows
                    )
                )
            }
        }

        if let snapshot = cursorSnapshot, snapshot.isEmpty == false {
            let labels = cursorWindowLabels(locale: locale)
            var windows: [UsageSummaryWindow] = []

            if let usedPercentage = snapshot.totalUsedPercentage {
                windows.append(
                    cursorWindow(
                        id: "cursor-total",
                        label: labels.total,
                        usedPercentage: usedPercentage,
                        resetsAt: snapshot.billingCycleEnd,
                        mode: mode,
                        now: now,
                        locale: locale
                    )
                )
            }
            if let usedPercentage = snapshot.apiUsedPercentage {
                windows.append(
                    cursorWindow(
                        id: "cursor-api",
                        label: labels.api,
                        usedPercentage: usedPercentage,
                        resetsAt: snapshot.billingCycleEnd,
                        mode: mode,
                        now: now,
                        locale: locale
                    )
                )
            }
            if let usedPercentage = snapshot.autoUsedPercentage {
                windows.append(
                    cursorWindow(
                        id: "cursor-auto",
                        label: labels.auto,
                        usedPercentage: usedPercentage,
                        resetsAt: snapshot.billingCycleEnd,
                        mode: mode,
                        now: now,
                        locale: locale
                    )
                )
            }

            if !windows.isEmpty {
                let title = ["Cursor", snapshot.planName]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                providers.append(
                    UsageSummaryProvider(
                        id: "cursor",
                        title: title,
                        subtitle: cursorSpendSummary(snapshot, locale: locale),
                        windows: windows
                    )
                )
            }
        }

        return providers
    }

    private nonisolated static func cursorWindow(
        id: String,
        label: String,
        usedPercentage: Double,
        resetsAt: Date?,
        mode: UsageValueMode,
        now: Date,
        locale: Locale
    ) -> UsageSummaryWindow {
        UsageSummaryWindow(
            id: id,
            label: label,
            valueText: valueText(for: usedPercentage, mode: mode, locale: locale),
            resetText: resetText(for: resetsAt, now: now, locale: locale),
            resetsAt: resetsAt,
            severity: severity(forUsedPercentage: usedPercentage),
            remainingPercentage: remainingPercentage(forUsedPercentage: usedPercentage)
        )
    }

    private nonisolated static func cursorWindowLabels(
        locale: Locale
    ) -> (total: String, api: String, auto: String) {
        switch locale.language.languageCode?.identifier {
        case "zh":
            return ("总量", "模型", "Auto")
        default:
            return ("All", "API", "Auto")
        }
    }

    private nonisolated static func cursorSpendSummary(
        _ snapshot: CursorUsageSnapshot,
        locale: Locale
    ) -> String? {
        guard let totalSpendCents = snapshot.totalSpendCents else { return nil }
        let amount = String(format: "$%.2f", Double(totalSpendCents) / 100)
        switch locale.language.languageCode?.identifier {
        case "zh":
            return "本期已用 \(amount)"
        default:
            return "\(amount) used this period"
        }
    }

    nonisolated static func shouldShowSummary(
        for route: IslandExpandedRoute,
        showUsage: Bool,
        providers: [UsageSummaryProvider]
    ) -> Bool {
        guard showUsage, !providers.isEmpty else {
            return false
        }

        switch route {
        case .sessionList, .hoverDashboard, .chat:
            return true
        case .attentionNotification, .completionNotification:
            return false
        }
    }

    nonisolated static func valueText(
        for usedPercentage: Double,
        mode: UsageValueMode,
        locale: Locale = .current
    ) -> String {
        guard ObservedNumber.percentage(usedPercentage) != nil else { return "—" }
        switch mode {
        case .used:
            return "\(ObservedNumber.roundedDisplay(usedPercentage))%"
        case .remaining:
            let remaining = max(0, 100 - usedPercentage)
            return remainingValueText(for: remaining, locale: locale)
        }
    }

    nonisolated static func remainingValueText(
        for remainingPercentage: Double,
        locale: Locale = .current
    ) -> String {
        guard ObservedNumber.percentage(remainingPercentage) != nil else { return "—" }
        let remaining = max(0, remainingPercentage)
        return "\(ObservedNumber.roundedDisplay(remaining))% \(localizedRemainingLabel(locale: locale))"
    }

    nonisolated static func resetText(
        for date: Date?,
        now: Date = .now,
        locale: Locale = .current
    ) -> String? {
        guard let date,
            let duration = remainingDurationString(until: date, now: now)
        else {
            return nil
        }

        switch locale.language.languageCode?.identifier {
        case "zh":
            return "\(duration) 后重置"
        default:
            return "Resets in \(duration)"
        }
    }

    nonisolated static func remainingDurationString(until date: Date, now: Date = .now) -> String? {
        guard let seconds = Int(exactly: date.timeIntervalSince(now).rounded(.towardZero)) else { return nil }
        guard seconds > 0 else {
            return nil
        }

        let totalMinutes = seconds / 60
        let days = totalMinutes / 1_440
        let remainingMinutesAfterDays = totalMinutes % 1_440
        let hours = remainingMinutesAfterDays / 60
        let minutes = remainingMinutesAfterDays % 60

        if days > 0, hours > 0 {
            return "\(days)d \(hours)h"
        }
        if days > 0 {
            return "\(days)d"
        }
        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "<1m"
    }

    nonisolated static func severity(forUsedPercentage usedPercentage: Double) -> UsageSummarySeverity {
        severity(forRemainingPercentage: remainingPercentage(forUsedPercentage: usedPercentage))
    }

    nonisolated static func severity(forRemainingPercentage remainingPercentage: Double) -> UsageSummarySeverity {
        if remainingPercentage >= 50 {
            return .healthy
        }
        if remainingPercentage >= 20 {
            return .warning
        }
        return .critical
    }

    nonisolated static func shouldShowFloatingBolt(for window: UsageSummaryWindow) -> Bool {
        window.remainingPercentage < 60
    }

    private nonisolated static func remainingPercentage(forUsedPercentage usedPercentage: Double) -> Double {
        max(0, 100 - usedPercentage)
    }

    private nonisolated static func localizedRemainingLabel(locale: Locale) -> String {
        switch locale.language.languageCode?.identifier {
        case "zh":
            return "剩余"
        default:
            return "left"
        }
    }
}
