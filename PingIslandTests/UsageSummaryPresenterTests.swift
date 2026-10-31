import XCTest

@testable import Ping_Island

final class UsageSummaryPresenterTests: XCTestCase {
    func testProvidersIncludeClaudeAndCodexSnapshots() {
        let providers = UsageSummaryPresenter.providers(
            claudeSnapshot: ClaudeUsageSnapshot(
                fiveHour: ClaudeUsageWindow(usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 1_760_000_000)),
                sevenDay: nil,
                cachedAt: nil
            ),
            codexSnapshot: CodexUsageSnapshot(
                sourceFilePath: "/tmp/rollout.jsonl",
                capturedAt: nil,
                planType: "pro",
                limitID: "codex",
                tokenUsage: nil,
                windows: [
                    CodexUsageWindow(
                        key: "primary",
                        label: "5h",
                        usedPercentage: 13,
                        leftPercentage: 87,
                        windowMinutes: 300,
                        resetsAt: Date(timeIntervalSince1970: 1_775_158_295)
                    )
                ]
            ),
            mode: .used,
            now: Date(timeIntervalSince1970: 1_759_999_000),
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(providers.map(\.title), ["Claude", "Codex"])
        XCTAssertEqual(providers.first?.windows.first?.valueText, "42%")
        XCTAssertEqual(providers.last?.windows.first?.valueText, "13%")
    }

    func testProvidersIncludeCursorPlanAPIAndAutoUsage() throws {
        let reset = Date(timeIntervalSince1970: 1_787_199_156)
        let providers = UsageSummaryPresenter.providers(
            claudeSnapshot: nil,
            codexSnapshot: nil,
            cursorSnapshot: CursorUsageSnapshot(
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                planName: "Pro",
                billingCycleEnd: reset,
                totalSpendCents: 8_007,
                includedSpendCents: 2_000,
                bonusSpendCents: 6_007,
                limitCents: 2_000,
                totalUsedPercentage: 23.2,
                apiUsedPercentage: 100,
                autoUsedPercentage: 10.07
            ),
            mode: .remaining,
            now: Date(timeIntervalSince1970: 1_775_000_000),
            locale: Locale(identifier: "zh_CN")
        )

        let provider = try XCTUnwrap(providers.first)
        XCTAssertEqual(provider.id, "cursor")
        XCTAssertEqual(provider.title, "Cursor · Pro")
        XCTAssertEqual(provider.subtitle, "本期已用 $80.07")
        XCTAssertEqual(provider.windows.map(\.label), ["总量", "模型", "Auto"])
        XCTAssertEqual(provider.windows.map(\.valueText), ["77% 剩余", "0% 剩余", "90% 剩余"])
        XCTAssertEqual(UsageSummaryPresenter.preferredBatteryWindow(for: provider)?.id, "cursor-total")
    }

    func testUsageProviderFollowsOnlyActivelyProcessingClient() {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let providers = usageProvidersForClientSelection()
        let recentIdleCursor = SessionState(
            sessionId: "cursor-idle",
            cwd: "/tmp/cursor",
            provider: .claude,
            clientInfo: cursorClientInfo(),
            phase: .idle,
            lastActivity: now
        )
        let olderActiveCodex = SessionState(
            sessionId: "codex-active",
            cwd: "/tmp/codex",
            provider: .codex,
            phase: .processing,
            lastActivity: now.addingTimeInterval(-60)
        )

        let selected = UsageSummaryPresenter.providersFollowingActiveClient(
            providers,
            sessions: [recentIdleCursor, olderActiveCodex]
        )

        XCTAssertEqual(selected.map(\.id), ["codex"])
    }

    func testUsageProviderUsesMostRecentlyActiveClientWhenBothAreRunning() {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let providers = usageProvidersForClientSelection()
        let olderActiveCodex = SessionState(
            sessionId: "codex-active",
            cwd: "/tmp/codex",
            provider: .codex,
            phase: .processing,
            lastActivity: now.addingTimeInterval(-60)
        )
        let recentActiveCursor = SessionState(
            sessionId: "cursor-active",
            cwd: "/tmp/cursor",
            provider: .claude,
            clientInfo: cursorClientInfo(),
            phase: .compacting,
            lastActivity: now
        )

        let selected = UsageSummaryPresenter.providersFollowingActiveClient(
            providers,
            sessions: [olderActiveCodex, recentActiveCursor]
        )

        XCTAssertEqual(selected.map(\.id), ["cursor"])
    }

    func testUsageProviderKeepsMostRecentSupportedClientWhenIdle() {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let providers = usageProvidersForClientSelection()
        let olderIdleCursor = SessionState(
            sessionId: "cursor-idle",
            cwd: "/tmp/cursor",
            provider: .claude,
            clientInfo: cursorClientInfo(),
            phase: .idle,
            lastActivity: now.addingTimeInterval(-60)
        )
        let recentIdleCodex = SessionState(
            sessionId: "codex-idle",
            cwd: "/tmp/codex",
            provider: .codex,
            phase: .idle,
            lastActivity: now
        )

        let selected = UsageSummaryPresenter.providersFollowingActiveClient(
            providers,
            sessions: [olderIdleCursor, recentIdleCodex]
        )

        XCTAssertEqual(selected.map(\.id), ["codex"])
    }

    func testUsageProviderDoesNotSubstituteCodexWhileCursorSnapshotIsUnavailable() {
        let activeCursor = SessionState(
            sessionId: "cursor-active",
            cwd: "/tmp/cursor",
            provider: .claude,
            clientInfo: cursorClientInfo(),
            phase: .processing
        )

        let selected = UsageSummaryPresenter.providersFollowingActiveClient(
            [usageProvidersForClientSelection()[0]],
            sessions: [activeCursor]
        )

        XCTAssertTrue(selected.isEmpty)
    }

    func testRemainingModeFormatsRemainingPercentInEnglish() {
        let valueText = UsageSummaryPresenter.valueText(
            for: 13,
            mode: .remaining,
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(valueText, "87% left")
    }

    func testPreferredBatteryWindowUsesSevenDayWhenAvailable() {
        let provider = UsageSummaryProvider(
            id: "codex",
            title: "Codex",
            windows: [
                UsageSummaryWindow(
                    id: "codex-primary",
                    label: "5h",
                    valueText: "24% left",
                    resetText: nil,
                    severity: .warning,
                    remainingPercentage: 24
                ),
                UsageSummaryWindow(
                    id: "codex-secondary",
                    label: "7d",
                    valueText: "82% left",
                    resetText: nil,
                    severity: .healthy,
                    remainingPercentage: 82
                ),
            ]
        )

        XCTAssertEqual(UsageSummaryPresenter.preferredBatteryWindow(for: provider)?.id, "codex-secondary")
    }

    func testSevenDayWindowSelectsOnlyRequestedProvider() {
        let providers = [
            UsageSummaryProvider(
                id: "claude",
                title: "Claude",
                windows: [
                    UsageSummaryWindow(
                        id: "claude-7d",
                        label: "7d",
                        valueText: "64% left",
                        resetText: nil,
                        severity: .healthy,
                        remainingPercentage: 64
                    )
                ]
            ),
            UsageSummaryProvider(
                id: "codex",
                title: "Codex",
                windows: [
                    UsageSummaryWindow(
                        id: "codex-5h",
                        label: "5h",
                        valueText: "22% left",
                        resetText: nil,
                        severity: .warning,
                        remainingPercentage: 22
                    ),
                    UsageSummaryWindow(
                        id: "codex-7d",
                        label: "7d",
                        valueText: "91% left",
                        resetText: nil,
                        severity: .healthy,
                        remainingPercentage: 91
                    ),
                ]
            ),
        ]

        XCTAssertEqual(
            UsageSummaryPresenter.sevenDayWindow(forProviderID: "codex", in: providers)?.id,
            "codex-7d"
        )
        XCTAssertNil(UsageSummaryPresenter.sevenDayWindow(forProviderID: "gemini", in: providers))
    }

    func testRemainingHelpTextIncludesAllWindows() {
        let provider = UsageSummaryProvider(
            id: "claude",
            title: "Claude",
            windows: [
                UsageSummaryWindow(
                    id: "claude-5h",
                    label: "5h",
                    valueText: "25% left",
                    resetText: "Resets in 2h",
                    severity: .warning,
                    remainingPercentage: 25
                ),
                UsageSummaryWindow(
                    id: "claude-7d",
                    label: "7d",
                    valueText: "91% left",
                    resetText: "Resets in 5d",
                    severity: .healthy,
                    remainingPercentage: 91
                ),
            ]
        )

        XCTAssertEqual(
            UsageSummaryPresenter.remainingHelpText(for: provider, locale: Locale(identifier: "en")),
            """
            Claude
            5h · 25% left
            7d · 91% left
            """
        )
    }

    func testShouldShowSummaryHidesAttentionAndCompletionRoutes() {
        let providers = [
            UsageSummaryProvider(
                id: "claude",
                title: "Claude",
                windows: [
                    UsageSummaryWindow(
                        id: "claude-5h",
                        label: "5h",
                        valueText: "42%",
                        resetText: nil,
                        severity: .healthy,
                        remainingPercentage: 58
                    )
                ]
            )
        ]
        let session = SessionState(sessionId: "session", cwd: "/tmp/demo", phase: .processing)
        let notification = SessionCompletionNotification(session: session, kind: .completed)

        XCTAssertTrue(
            UsageSummaryPresenter.shouldShowSummary(
                for: .sessionList,
                showUsage: true,
                providers: providers
            )
        )
        XCTAssertFalse(
            UsageSummaryPresenter.shouldShowSummary(
                for: .attentionNotification(session),
                showUsage: true,
                providers: providers
            )
        )
        XCTAssertFalse(
            UsageSummaryPresenter.shouldShowSummary(
                for: .completionNotification(notification),
                showUsage: true,
                providers: providers
            )
        )
    }

    func testSeverityUsesRemainingQuotaThresholds() {
        XCTAssertEqual(UsageSummaryPresenter.severity(forRemainingPercentage: 100), .healthy)
        XCTAssertEqual(UsageSummaryPresenter.severity(forRemainingPercentage: 50), .healthy)
        XCTAssertEqual(UsageSummaryPresenter.severity(forRemainingPercentage: 49), .warning)
        XCTAssertEqual(UsageSummaryPresenter.severity(forRemainingPercentage: 20), .warning)
        XCTAssertEqual(UsageSummaryPresenter.severity(forRemainingPercentage: 19), .critical)
        XCTAssertEqual(UsageSummaryPresenter.severity(forRemainingPercentage: 0), .critical)

        XCTAssertEqual(UsageSummaryPresenter.severity(forUsedPercentage: 50), .healthy)
        XCTAssertEqual(UsageSummaryPresenter.severity(forUsedPercentage: 51), .warning)
        XCTAssertEqual(UsageSummaryPresenter.severity(forUsedPercentage: 81), .critical)
    }

    func testFloatingBoltShowsOnlyBelowSixtyPercentRemaining() {
        let sixtyRemaining = UsageSummaryWindow(
            id: "sixty",
            label: "5h",
            valueText: "60% left",
            resetText: nil,
            severity: .healthy,
            remainingPercentage: 60
        )
        let belowSixtyRemaining = UsageSummaryWindow(
            id: "below-sixty",
            label: "5h",
            valueText: "59% left",
            resetText: nil,
            severity: .healthy,
            remainingPercentage: 59
        )

        XCTAssertFalse(UsageSummaryPresenter.shouldShowFloatingBolt(for: sixtyRemaining))
        XCTAssertTrue(UsageSummaryPresenter.shouldShowFloatingBolt(for: belowSixtyRemaining))
    }

    private func usageProvidersForClientSelection() -> [UsageSummaryProvider] {
        [
            UsageSummaryProvider(
                id: "codex",
                title: "Codex",
                windows: [
                    UsageSummaryWindow(
                        id: "codex-7d",
                        label: "7d",
                        valueText: "98% left",
                        resetText: nil,
                        severity: .healthy,
                        remainingPercentage: 98
                    )
                ]
            ),
            UsageSummaryProvider(
                id: "cursor",
                title: "Cursor · Pro",
                windows: [
                    UsageSummaryWindow(
                        id: "cursor-total",
                        label: "All",
                        valueText: "76% left",
                        resetText: nil,
                        severity: .healthy,
                        remainingPercentage: 76
                    )
                ]
            ),
        ]
    }

    private func cursorClientInfo() -> SessionClientInfo {
        SessionClientInfo(
            kind: .claudeCode,
            profileID: "cursor-local",
            name: "Cursor"
        )
    }
}
