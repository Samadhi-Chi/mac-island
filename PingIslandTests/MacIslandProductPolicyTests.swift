import XCTest

@testable import Ping_Island

final class MacIslandProductPolicyTests: XCTestCase {
    func testSharedRuntimeIdentityFollowsTheActiveBundleWithoutPinningAUser() {
        XCTAssertEqual(
            MacIslandProductPolicy.resolvedRuntimeBundleIdentifier("local.sun.macisland"),
            "local.sun.macisland"
        )
        XCTAssertEqual(
            MacIslandProductPolicy.resolvedRuntimeBundleIdentifier("local.samadhi.macisland"),
            "local.samadhi.macisland"
        )
        XCTAssertEqual(
            MacIslandProductPolicy.resolvedRuntimeBundleIdentifier(nil),
            "local.shared.macisland"
        )
        XCTAssertEqual(
            BridgeRuntimePaths.appGroupIdentifier,
            "group.\(MacIslandProductPolicy.runtimeBundleIdentifier)"
        )
    }

    func testV1PolicyIsLocalMonitorOnly() {
        XCTAssertTrue(MacIslandProductPolicy.monitorOnly)
        XCTAssertFalse(MacIslandProductPolicy.analyticsEnabled)
        XCTAssertFalse(MacIslandProductPolicy.updatesEnabled)
        XCTAssertFalse(MacIslandProductPolicy.automaticallyInstallsHooks)
        XCTAssertFalse(MacIslandProductPolicy.mascotsEnabled)
        XCTAssertFalse(MacIslandProductPolicy.soundsEnabled)
        XCTAssertFalse(MacIslandProductPolicy.automaticPanelPresentationEnabled)
        XCTAssertFalse(MacIslandProductPolicy.ambientAttentionMotionEnabled)
        XCTAssertTrue(MacIslandProductPolicy.usageTrackingEnabled)
        XCTAssertFalse(MacIslandProductPolicy.hookPayloadLoggingEnabled)
        XCTAssertFalse(MacIslandProductPolicy.brandedClientAssetsEnabled)
        XCTAssertTrue(MacIslandProductPolicy.privacyShieldEnabled)
        XCTAssertFalse(MacIslandProductPolicy.contentDerivedTitlesEnabled)
        XCTAssertFalse(MacIslandProductPolicy.conversationPreviewsEnabled)
        XCTAssertTrue(MacIslandProductPolicy.localConversationTurnsEnabled)
        XCTAssertEqual(MacIslandProductPolicy.defaultScreenContentVisibility, .titles)
        XCTAssertFalse(MacIslandProductPolicy.onScreenPrivacyShieldEnabled)
        XCTAssertTrue(MacIslandProductPolicy.conversationDetailsVisibleByDefault)
        XCTAssertTrue(MacIslandProductPolicy.localProjectAndThreadTitlesEnabled)
        XCTAssertEqual(MacIslandProductPolicy.defaultContentFontSize, 12)
        XCTAssertEqual(MacIslandProductPolicy.defaultCompletionCardHeight, 90)
        XCTAssertEqual(MacIslandProductPolicy.defaultMaximumPanelHeight, 560)
        XCTAssertEqual(MacIslandProductPolicy.defaultMaximumPanelWidth, 640)
    }

    func testPresentationPolicyKeepsHoverLightweightAndNonActivating() {
        XCTAssertEqual(MacIslandPresentationPolicy.preferredPanelWidth, 600)
        XCTAssertEqual(MacIslandPresentationPolicy.expandedConversationCardHeight, 156)
        XCTAssertEqual(MacIslandPresentationPolicy.panelHoverOpenDelay, 0.13)
        XCTAssertEqual(MacIslandPresentationPolicy.panelHoverCloseDelay, 0.20)
        XCTAssertFalse(MacIslandPresentationPolicy.shouldBecomeKey(openReason: .hover))
        XCTAssertFalse(MacIslandPresentationPolicy.shouldBecomeKey(openReason: .notification))
        XCTAssertFalse(MacIslandPresentationPolicy.shouldBecomeKey(openReason: .boot))
        XCTAssertTrue(MacIslandPresentationPolicy.shouldBecomeKey(openReason: .click))

        let screenFrame = CGRect(x: 100, y: 50, width: 1710, height: 1112)
        let windowFrame = MacIslandPresentationPolicy.dockedWindowFrame(in: screenFrame)
        XCTAssertEqual(windowFrame.width, 696)
        XCTAssertEqual(windowFrame.height, 624)
        XCTAssertEqual(windowFrame.midX, screenFrame.midX)
        XCTAssertEqual(windowFrame.maxY, screenFrame.maxY)
    }

    func testPresentationPolicyShowsAtMostTheExplicitlyExpandedDetail() {
        XCTAssertFalse(
            MacIslandPresentationPolicy.shouldShowConversationDetail(
                isExpanded: false,
                detailsEnabled: true,
                usesTitleOnlyPresentation: false
            )
        )
        XCTAssertTrue(
            MacIslandPresentationPolicy.shouldShowConversationDetail(
                isExpanded: true,
                detailsEnabled: true,
                usesTitleOnlyPresentation: false
            )
        )
        XCTAssertFalse(
            MacIslandPresentationPolicy.shouldShowConversationDetail(
                isExpanded: true,
                detailsEnabled: false,
                usesTitleOnlyPresentation: false
            )
        )
        XCTAssertFalse(
            MacIslandPresentationPolicy.shouldShowConversationDetail(
                isExpanded: true,
                detailsEnabled: true,
                usesTitleOnlyPresentation: true
            )
        )
        XCTAssertFalse(MacIslandPresentationPolicy.shouldUseScrollContainer(sessionCount: 3))
        XCTAssertTrue(MacIslandPresentationPolicy.shouldUseScrollContainer(sessionCount: 4))
        XCTAssertTrue(
            MacIslandPresentationPolicy.conversationDetailsEnabled(
                agentActivityDetailsEnabled: false
            )
        )

        XCTAssertTrue(
            MacIslandPresentationPolicy.shouldShowInlineConversationPreview(
                isExpanded: false,
                usesMinimalCompactPresentation: false
            )
        )
        XCTAssertTrue(
            MacIslandPresentationPolicy.shouldShowInlineConversationPreview(
                isExpanded: true,
                usesMinimalCompactPresentation: false
            )
        )
    }

    func testPersistedAssociationDropsContentDerivedSessionName() {
        let session = SessionState(
            sessionId: "private-association",
            cwd: "/tmp/project",
            provider: .codex,
            clientInfo: .codexApp(threadId: "private-association"),
            sessionName: "SECRET_PROMPT_SHOULD_NOT_BE_PERSISTED",
            phase: .processing
        )

        let association = PersistedSessionAssociation(session: session)
        XCTAssertNil(association.sessionName)
    }

    func testCodexDiagnosticsDoNotExportOnScreenConversationContent() async {
        let store = SessionStore.shared
        let sessionId = "diagnostics-redaction-\(UUID().uuidString)"
        let secret = "SECRET_CONVERSATION_CONTENT"
        let timestamp = Date()
        let snapshot = CodexThreadSnapshot(
            threadId: sessionId,
            name: "\(secret)_THREAD",
            preview: "\(secret)_PREVIEW",
            cwd: "/tmp/SECRET_PRIVATE_PROJECT",
            clientInfo: SessionClientInfo(
                kind: .codexApp,
                profileID: "codex-app",
                name: "Codex App",
                bundleIdentifier: "com.openai.codex",
                sessionFilePath: "/tmp/SECRET_PRIVATE_ROLLOUT.jsonl"
            ),
            intervention: nil,
            createdAt: timestamp,
            updatedAt: timestamp,
            phase: .processing,
            historyItems: [
                ChatHistoryItem(
                    id: "secret-response",
                    type: .assistant("\(secret)_RESPONSE"),
                    timestamp: timestamp
                )
            ],
            conversationInfo: ConversationInfo(
                summary: nil,
                lastMessage: "\(secret)_RESPONSE",
                lastMessageRole: "assistant",
                lastToolName: nil,
                firstUserMessage: "\(secret)_PROMPT",
                lastUserMessageDate: timestamp
            ),
            latestTurnId: "turn-secret",
            latestResponseText: "\(secret)_RESPONSE",
            latestResponsePhase: "final",
            latestUserText: "\(secret)_PROMPT"
        )

        await store.syncCodexThreadSnapshot(snapshot)
        let exported = await store.diagnosticsSnapshot().first { $0.sessionId == sessionId }

        XCTAssertEqual(exported?.displayTitle, "Codex")
        XCTAssertEqual(exported?.effectiveDisplayTitle, "Codex")
        XCTAssertEqual(exported?.projectName, "Codex")
        XCTAssertNil(exported?.sessionName)
        XCTAssertNil(exported?.previewText)
        XCTAssertNil(exported?.lastMessage)
        XCTAssertNil(exported?.codexSubagentLabel)
        XCTAssertNil(exported?.cwd)
        XCTAssertNil(exported?.sessionFilePath)

        await store.process(.sessionArchived(sessionId: sessionId))
    }

    func testOnlyExplicitObservationClientsAreAccepted() {
        XCTAssertTrue(
            MacIslandProductPolicy.supportsSession(
                provider: .codex,
                clientInfo: .codexCLI()
            )
        )
        XCTAssertTrue(
            MacIslandProductPolicy.supportsSession(
                provider: .claude,
                clientInfo: SessionClientInfo(
                    kind: .custom,
                    profileID: "cursor-hooks",
                    name: "Cursor"
                )
            )
        )
        XCTAssertTrue(
            MacIslandProductPolicy.supportsSession(
                provider: .claude,
                clientInfo: SessionClientInfo(
                    kind: .claudeCode,
                    profileID: "claude-code",
                    name: "Claude Code",
                    origin: "cli",
                    threadSource: "claude-hooks"
                )
            )
        )
        XCTAssertTrue(
            MacIslandProductPolicy.supportsSession(
                provider: .claude,
                clientInfo: SessionClientInfo(
                    kind: .custom,
                    profileID: "opencode",
                    name: "OpenCode",
                    origin: "desktop",
                    threadSource: "opencode-plugin"
                )
            )
        )
        XCTAssertTrue(
            MacIslandProductPolicy.supportsSession(
                provider: .claude,
                clientInfo: SessionClientInfo(
                    kind: .custom,
                    profileID: "hermes",
                    name: "Hermes",
                    origin: "cli",
                    threadSource: "hermes-plugin"
                )
            )
        )
        XCTAssertFalse(
            MacIslandProductPolicy.supportsSession(
                provider: .claude,
                clientInfo: SessionClientInfo(
                    kind: .custom,
                    profileID: "claude-desktop",
                    name: "Claude Desktop",
                    origin: "desktop"
                )
            )
        )
        XCTAssertFalse(
            MacIslandProductPolicy.supportsSession(
                provider: .claude,
                clientInfo: SessionClientInfo(
                    kind: .custom,
                    profileID: "hermes",
                    name: "Hermes",
                    origin: "cron",
                    threadSource: "hermes-plugin"
                )
            )
        )
        XCTAssertFalse(
            MacIslandProductPolicy.supportsSession(
                provider: .gemini,
                clientInfo: SessionClientInfo(kind: .custom, name: "Gemini CLI")
            )
        )
    }

    func testObservationHookProfilesAreExposed() {
        XCTAssertEqual(
            Set(ClientProfileRegistry.supportedManagedHookProfiles.map(\.id)),
            ["claude-hooks", "codex-hooks", "cursor-hooks", "opencode-hooks", "hermes-hooks", "dsh-hooks"]
        )
        XCTAssertEqual(
            Set(ClientProfileRegistry.supportedIDEExtensionProfiles.map(\.id)),
            ["cursor-extension"]
        )
    }

    func testMonitorOnlyPolicySuppressesRespondableApprovalControls() {
        let session = SessionState(
            sessionId: "approval-session",
            cwd: "/tmp/project",
            phase: .waitingForApproval(
                PermissionContext(
                    toolUseId: "tool-1",
                    toolName: "Bash",
                    toolInput: nil,
                    receivedAt: Date()
                )
            )
        )

        XCTAssertTrue(session.shouldSuppressInAppPromptControls(routePromptsToTerminal: false))
    }

    func testVisibleSessionBoundaryDropsPersistedUnsupportedClients() {
        let sessions = [
            SessionState(
                sessionId: "codex",
                cwd: "/tmp/codex",
                provider: .codex,
                clientInfo: .codexCLI()
            ),
            SessionState(
                sessionId: "cursor",
                cwd: "/tmp/cursor",
                provider: .claude,
                clientInfo: SessionClientInfo(
                    kind: .custom,
                    profileID: "cursor-hooks",
                    name: "Cursor"
                )
            ),
            SessionState(
                sessionId: "legacy-claude",
                cwd: "/tmp/claude",
                provider: .claude,
                clientInfo: SessionClientInfo(kind: .claudeCode, name: "Claude Code")
            ),
        ]

        XCTAssertEqual(
            SessionMonitor.productSupportedSessions(from: sessions).map(\.sessionId),
            ["codex", "cursor", "legacy-claude"]
        )
    }

    func testCursorThreadsInSameWorkspaceAreNotCollapsedByClaudeDeduplication() {
        let cursorClient = SessionClientInfo(
            kind: .custom,
            profileID: "cursor-local",
            name: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92"
        )
        let sessions = [
            SessionState(
                sessionId: "cursor-thread-1",
                cwd: "/tmp/shared-workspace",
                provider: .claude,
                clientInfo: cursorClient,
                sessionName: "Thread One"
            ),
            SessionState(
                sessionId: "cursor-thread-2",
                cwd: "/tmp/shared-workspace",
                provider: .claude,
                clientInfo: cursorClient,
                sessionName: "Thread Two"
            ),
        ]

        XCTAssertEqual(
            SessionMonitor.deduplicateSameProjectClaudeSessions(from: sessions).map(\.sessionId),
            ["cursor-thread-1", "cursor-thread-2"]
        )
    }

    func testMacIslandClientGlyphUsesAllSupportedIdentities() {
        let codexSession = SessionState(
            sessionId: "codex-glyph",
            cwd: "/tmp/codex",
            provider: .codex,
            clientInfo: .codexApp(threadId: "codex-glyph")
        )
        let cursorSession = SessionState(
            sessionId: "cursor-glyph",
            cwd: "/tmp/cursor",
            provider: .claude,
            clientInfo: SessionClientInfo(
                kind: .custom,
                profileID: "cursor-local",
                name: "Cursor",
                bundleIdentifier: "com.todesktop.230313mzl4w4u92"
            )
        )

        let claudeSession = observedSession(
            id: "claude-glyph",
            profileID: "claude-code",
            name: "Claude Code",
            origin: "cli",
            source: "claude-hooks",
            kind: .claudeCode
        )
        let openCodeSession = observedSession(
            id: "opencode-glyph",
            profileID: "opencode",
            name: "OpenCode",
            origin: "desktop",
            source: "opencode-plugin"
        )
        let hermesSession = observedSession(
            id: "hermes-glyph",
            profileID: "hermes",
            name: "Hermes",
            origin: "cli",
            source: "hermes-plugin"
        )

        XCTAssertEqual(MacIslandClientGlyphKind(session: codexSession), .codex)
        XCTAssertEqual(MacIslandClientGlyphKind(session: cursorSession), .cursor)
        XCTAssertEqual(MacIslandClientGlyphKind(session: claudeSession), .claudeCode)
        XCTAssertEqual(MacIslandClientGlyphKind(session: openCodeSession), .openCode)
        XCTAssertEqual(MacIslandClientGlyphKind(session: hermesSession), .hermes)
    }

    func testClaudeBGlyphUsesTwelveAlternatingRaysAndContractsWithoutRotation() {
        XCTAssertEqual(MacIslandClaudePixelArt.rayCount, 12)
        for rayIndex in 0..<MacIslandClaudePixelArt.rayCount {
            XCTAssertEqual(MacIslandClaudePixelArt.segments(forRay: rayIndex).count, 3)
        }
        XCTAssertEqual(
            MacIslandClaudePixelArt.segments(forRay: 0),
            MacIslandClaudePixelArt.segments(forRay: 6)
        )
        XCTAssertEqual(
            MacIslandClaudePixelArt.core,
            MacIslandPixelRect(x: 28, y: 28, width: 8, height: 8)
        )

        let duration = MacIslandClaudeGlyphMotion.cycleDuration
        let contracted = MacIslandClaudeGlyphMotion.state(at: duration * 0.5)
        XCTAssertEqual(contracted.rayTranslationY, 9, accuracy: 0.0001)
        XCTAssertEqual(contracted.rayScaleY, 0.42, accuracy: 0.0001)
        XCTAssertEqual(contracted.rayOpacity, 0.68, accuracy: 0.0001)

        let released = MacIslandClaudeGlyphMotion.state(at: duration * 0.66)
        XCTAssertEqual(released.coreScale, 1.25, accuracy: 0.0001)
        XCTAssertEqual(released.coreOpacity, 1, accuracy: 0.0001)

        XCTAssertEqual(
            MacIslandClaudeGlyphMotion.state(at: 0),
            MacIslandClaudeGlyphMotion.state(at: duration)
        )
        XCTAssertEqual(MacIslandClaudeGlyphMotion.state(at: .nan), .staticState)
    }

    func testOpenCodeEGlyphUsesGrayscaleBracketsWithHorizontalOnlyMotion() {
        XCTAssertEqual(MacIslandOpenCodePixelArt.leftBracket.count, 5)
        XCTAssertEqual(MacIslandOpenCodePixelArt.rightBracket.count, 5)
        XCTAssertEqual(
            Set(MacIslandOpenCodePixelArt.leftBracket.map(\.tone)),
            Set([.light, .mid, .dark])
        )
        XCTAssertEqual(
            Set(MacIslandOpenCodePixelArt.rightBracket.map(\.tone)),
            Set([.light, .mid, .dark])
        )

        let duration = MacIslandOpenCodeGlyphMotion.cycleDuration
        let outward = MacIslandOpenCodeGlyphMotion.state(at: 0)
        XCTAssertEqual(outward.leftTranslationX, -5, accuracy: 0.0001)
        XCTAssertEqual(outward.rightTranslationX, 5, accuracy: 0.0001)

        let inward = MacIslandOpenCodeGlyphMotion.state(at: duration / 2)
        XCTAssertEqual(inward.leftTranslationX, 4, accuracy: 0.0001)
        XCTAssertEqual(inward.rightTranslationX, -4, accuracy: 0.0001)
        XCTAssertEqual(MacIslandOpenCodeGlyphMotion.state(at: .infinity), .staticState)
    }

    func testHermesAGlyphHasTwoPlainEyesNoMouthAndSeparatedHeadphones() {
        XCTAssertEqual(
            MacIslandHermesPixelArt.facialFeatures,
            [
                MacIslandPixelRect(x: 25, y: 31, width: 4, height: 5),
                MacIslandPixelRect(x: 36, y: 31, width: 4, height: 5),
            ]
        )
        XCTAssertEqual(MacIslandHermesPixelArt.facialFeatures.count, 2)
        XCTAssertEqual(
            MacIslandHermesPixelArt.eyeBounds,
            MacIslandPixelRect(x: 25, y: 31, width: 15, height: 5)
        )

        let blinkDuration = MacIslandHermesGlyphMotion.blinkCycleDuration
        XCTAssertEqual(
            MacIslandHermesGlyphMotion.state(at: blinkDuration * 0.61).eyePhase,
            .open
        )
        let halfBlink = MacIslandHermesGlyphMotion.state(at: blinkDuration * 0.63)
        XCTAssertEqual(halfBlink.eyePhase, .halfClosed)
        XCTAssertEqual(halfBlink.eyeScaleX, 1.15, accuracy: 0.0001)
        XCTAssertEqual(halfBlink.eyeScaleY, 0.6, accuracy: 0.0001)

        let closedBlink = MacIslandHermesGlyphMotion.state(at: blinkDuration * 0.65)
        XCTAssertEqual(closedBlink.eyePhase, .closed)
        XCTAssertEqual(closedBlink.eyeScaleX, 1.35, accuracy: 0.0001)
        XCTAssertEqual(closedBlink.eyeScaleY, 0.16, accuracy: 0.0001)

        XCTAssertEqual(
            MacIslandHermesGlyphMotion.state(at: blinkDuration * 0.83).eyePhase,
            .closed
        )
        XCTAssertEqual(
            MacIslandHermesGlyphMotion.state(at: blinkDuration * 0.90).eyePhase,
            .open
        )

        let headphoneDuration = MacIslandHermesGlyphMotion.headphoneCycleDuration
        XCTAssertEqual(
            MacIslandHermesGlyphMotion.state(at: 0).headphoneTranslationY,
            -2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            MacIslandHermesGlyphMotion.state(at: headphoneDuration / 2).headphoneTranslationY,
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(MacIslandHermesGlyphMotion.state(at: .nan), .staticState)
    }

    func testCodexC12GlyphUsesFourEqualSteppedCheckerboardTiles() {
        XCTAssertEqual(
            MacIslandCodexPixelMotion.tileRows,
            [".###.", "#####", "#####", "#####", ".###."]
        )
        XCTAssertTrue(MacIslandCodexPixelMotion.tileRows.allSatisfy { $0.count == 5 })

        XCTAssertTrue(MacIslandCodexPixelMotion.usesDarkColor(tileIndex: 0))
        XCTAssertFalse(MacIslandCodexPixelMotion.usesDarkColor(tileIndex: 1))
        XCTAssertFalse(MacIslandCodexPixelMotion.usesDarkColor(tileIndex: 2))
        XCTAssertTrue(MacIslandCodexPixelMotion.usesDarkColor(tileIndex: 3))
        XCTAssertEqual(MacIslandCodexPixelMotion.unitOutline.count, 12)
    }

    func testCodexC12MotionUsesClockwiseContinuousBrightnessChase() {
        let duration = MacIslandCodexPixelMotion.cycleDuration

        XCTAssertEqual(
            MacIslandCodexPixelMotion.opacity(tileIndex: 0, at: 0),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            MacIslandCodexPixelMotion.opacity(tileIndex: 1, at: duration / 4),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            MacIslandCodexPixelMotion.opacity(tileIndex: 3, at: duration / 2),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            MacIslandCodexPixelMotion.opacity(tileIndex: 2, at: duration * 3 / 4),
            1,
            accuracy: 0.0001
        )

        for tileIndex in 0..<4 {
            for sample in 0...24 {
                let value = MacIslandCodexPixelMotion.opacity(
                    tileIndex: tileIndex,
                    at: duration * Double(sample) / 24
                )
                XCTAssertGreaterThanOrEqual(value, MacIslandCodexPixelMotion.minimumOpacity)
                XCTAssertLessThanOrEqual(value, 1)
            }

            XCTAssertEqual(
                MacIslandCodexPixelMotion.opacity(tileIndex: tileIndex, at: 0.37),
                MacIslandCodexPixelMotion.opacity(
                    tileIndex: tileIndex,
                    at: 0.37 + duration
                ),
                accuracy: 0.0001
            )
        }
        XCTAssertEqual(MacIslandCodexPixelMotion.opacity(tileIndex: -1, at: 0), 1)
        XCTAssertEqual(MacIslandCodexPixelMotion.opacity(tileIndex: 0, at: .nan), 1)

        XCTAssertEqual(MacIslandCodexPixelMotion.rotationDegrees(at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(
            MacIslandCodexPixelMotion.rotationDegrees(at: duration / 4),
            90,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            MacIslandCodexPixelMotion.rotationDegrees(at: duration),
            0,
            accuracy: 0.0001
        )
        for sample in 0...24 {
            let time = duration * Double(sample) / 24
            XCTAssertGreaterThanOrEqual(
                MacIslandCodexPixelMotion.scale(at: time),
                MacIslandCodexPixelMotion.minimumScale
            )
            XCTAssertLessThanOrEqual(
                MacIslandCodexPixelMotion.scale(at: time),
                MacIslandCodexPixelMotion.maximumScale
            )
            XCTAssertGreaterThanOrEqual(
                MacIslandCodexPixelMotion.breathingOpacity(at: time),
                MacIslandCodexPixelMotion.minimumBreathingOpacity
            )
            XCTAssertLessThanOrEqual(
                MacIslandCodexPixelMotion.breathingOpacity(at: time),
                1
            )
        }
    }

    func testClientGlyphMotionAnimatesOnlyWorkingSupportedClients() {
        XCTAssertTrue(
            MacIslandClientGlyphMotionPolicy.shouldAnimate(
                kind: .codex,
                status: .working,
                reduceMotion: false,
                animationLevel: .full
            )
        )
        for kind in [
            MacIslandClientGlyphKind.claudeCode,
            .openCode,
            .hermes,
        ] {
            XCTAssertTrue(
                MacIslandClientGlyphMotionPolicy.shouldAnimate(
                    kind: kind,
                    status: .working,
                    reduceMotion: false,
                    animationLevel: .full
                )
            )
            XCTAssertFalse(
                MacIslandClientGlyphMotionPolicy.shouldAnimate(
                    kind: kind,
                    status: .idle,
                    reduceMotion: false,
                    animationLevel: .full
                )
            )
        }
        XCTAssertTrue(
            MacIslandClientGlyphMotionPolicy.shouldAnimate(
                kind: .cursor,
                status: .working,
                reduceMotion: false,
                animationLevel: .full
            )
        )
        XCTAssertFalse(
            MacIslandClientGlyphMotionPolicy.shouldAnimate(
                kind: .cursor,
                status: .idle,
                reduceMotion: false,
                animationLevel: .full
            )
        )
        XCTAssertFalse(
            MacIslandClientGlyphMotionPolicy.shouldAnimate(
                kind: .cursor,
                status: .warning,
                reduceMotion: false,
                animationLevel: .full
            )
        )
        XCTAssertFalse(
            MacIslandClientGlyphMotionPolicy.shouldAnimate(
                kind: .fallback,
                status: .working,
                reduceMotion: false,
                animationLevel: .full
            )
        )
        XCTAssertFalse(
            MacIslandClientGlyphMotionPolicy.shouldAnimate(
                kind: .codex,
                status: .idle,
                reduceMotion: false,
                animationLevel: .full
            )
        )
        XCTAssertFalse(
            MacIslandClientGlyphMotionPolicy.shouldAnimate(
                kind: .codex,
                status: .working,
                reduceMotion: true,
                animationLevel: .full
            )
        )
        XCTAssertFalse(
            MacIslandClientGlyphMotionPolicy.shouldAnimate(
                kind: .codex,
                status: .working,
                reduceMotion: false,
                animationLevel: .staticFrames
            )
        )
    }

    func testClosedClientGlyphOnlyAppearsForGenuinelyRunningPhases() {
        let permission = PermissionContext(
            toolUseId: "tool-1",
            toolName: "Read",
            toolInput: nil,
            receivedAt: .distantPast
        )

        XCTAssertTrue(
            MacIslandPresentationPolicy.shouldShowClosedClientGlyph(for: .processing)
        )
        XCTAssertTrue(
            MacIslandPresentationPolicy.shouldShowClosedClientGlyph(for: .compacting)
        )
        XCTAssertFalse(
            MacIslandPresentationPolicy.shouldShowClosedClientGlyph(for: .idle)
        )
        XCTAssertFalse(
            MacIslandPresentationPolicy.shouldShowClosedClientGlyph(for: .ended)
        )
        XCTAssertFalse(
            MacIslandPresentationPolicy.shouldShowClosedClientGlyph(for: .waitingForInput)
        )
        XCTAssertFalse(
            MacIslandPresentationPolicy.shouldShowClosedClientGlyph(
                for: .waitingForApproval(permission)
            )
        )
        XCTAssertFalse(
            MacIslandPresentationPolicy.shouldShowClosedClientGlyph(for: nil)
        )
    }

    func testPersonalAgentGlyphsUseHoverWithoutClaimingWorkingOrDotIdentity() {
        XCTAssertEqual(MacIslandClientGlyphKind(personalAgent: .muse), .muse)
        XCTAssertEqual(MacIslandClientGlyphKind(personalAgent: .grokBot), .grokBot)
        XCTAssertEqual(MacIslandClientGlyphKind(personalAgent: .dot), .fallback)
        for kind in [MacIslandClientGlyphKind.muse, .grokBot] {
            XCTAssertFalse(
                MacIslandClientGlyphMotionPolicy.shouldAnimate(
                    kind: kind, status: .working,
                    reduceMotion: false, animationLevel: .full))
            for level in [EnergyAnimationLevel.full, .reduced] {
                XCTAssertTrue(
                    MacIslandClientGlyphMotionPolicy.shouldAnimate(
                        kind: kind, status: .idle,
                        reduceMotion: false, animationLevel: level, interactionActive: true))
            }
            XCTAssertFalse(
                MacIslandClientGlyphMotionPolicy.shouldAnimate(
                    kind: kind, status: .idle,
                    reduceMotion: true, animationLevel: .full, interactionActive: true))
            XCTAssertFalse(
                MacIslandClientGlyphMotionPolicy.shouldAnimate(
                    kind: kind, status: .idle,
                    reduceMotion: false, animationLevel: .staticFrames, interactionActive: true))
        }
        XCTAssertFalse(
            MacIslandClientGlyphMotionPolicy.shouldAnimate(
                kind: .codex, status: .idle,
                reduceMotion: false, animationLevel: .full, interactionActive: true))
    }

    func testPersonalAgentPixelMotionKeepsCrispSilhouettesAndStaticFallbacks() {
        for kind in MacIslandPersonalAgentGlyph.allCases {
            let still = MacIslandPersonalAgentPixelArt.pixels(for: kind)
            XCTAssertFalse(still.isEmpty)
            XCTAssertEqual(Set(still.map(\.id)).count, still.count)
            XCTAssertTrue(still.allSatisfy { (1..<15).contains($0.x) && (1..<15).contains($0.y) })
            for invalid in [Double.nan, Double.infinity, -Double.infinity] {
                XCTAssertEqual(MacIslandPersonalAgentPixelArt.pixels(for: kind, at: invalid), still)
            }
            for index in 0..<42 {
                let time = Double(index) * kind.cycleDuration / 42
                let frame = MacIslandPersonalAgentPixelArt.pixels(for: kind, at: time)
                XCTAssertEqual(frame.map(\.id), still.map(\.id))
                XCTAssertTrue(
                    frame.allSatisfy {
                        (0...1).contains($0.red) && (0...1).contains($0.green) && (0...1).contains($0.blue)
                    })
                let next = MacIslandPersonalAgentPixelArt.pixels(for: kind, at: time + kind.cycleDuration)
                XCTAssertEqual(frame.map(\.id), next.map(\.id))
                for pair in zip(frame, next) {
                    XCTAssertEqual(pair.0.red, pair.1.red, accuracy: 0.00001)
                    XCTAssertEqual(pair.0.green, pair.1.green, accuracy: 0.00001)
                    XCTAssertEqual(pair.0.blue, pair.1.blue, accuracy: 0.00001)
                }
            }
        }
        let museStill = MacIslandPersonalAgentPixelArt.pixels(for: .muse)
        let museLight = MacIslandPersonalAgentPixelArt.pixels(for: .muse, at: 1.6)
        XCTAssertNotEqual(museStill, museLight)
        XCTAssertTrue(museLight.allSatisfy { $0.blue > $0.green && $0.green > $0.red })
        let grokStill = MacIslandPersonalAgentPixelArt.pixels(for: .grokBot)
        let grokLook = MacIslandPersonalAgentPixelArt.pixels(for: .grokBot, at: 1.55)
        XCTAssertEqual(
            grokStill.filter { $0.isDetail }.map(\.x).min()! + 1,
            grokLook.filter { $0.isDetail }.map(\.x).min())
        XCTAssertEqual(grokStill.filter { $0.isDetail }.count, grokLook.filter { $0.isDetail }.count)
        XCTAssertEqual(grokStill.filter { $0.isDetail }.map(\.y), grokLook.filter { $0.isDetail }.map(\.y))
    }

    func testCursorCFacetArtOpensWithinNineteenPixelGridWithoutCenterDot() {
        let closed = MacIslandCursorPixelArt.cells(separation: 0)
        let opened = MacIslandCursorPixelArt.cells(separation: 1)

        XCTAssertEqual(MacIslandCursorPixelArt.gridSize, 19)
        XCTAssertEqual(closed.count, 177)
        XCTAssertEqual(opened.count, closed.count)
        XCTAssertEqual(closed.map(\.id), opened.map(\.id))
        XCTAssertEqual(Set(closed.map(\.facet.rawValue)), Set(0..<4))
        XCTAssertEqual(closed.map(\.x).min(), 1)
        XCTAssertEqual(closed.map(\.x).max(), 17)
        XCTAssertEqual(closed.map(\.y).min(), 1)
        XCTAssertEqual(closed.map(\.y).max(), 17)
        XCTAssertEqual(opened.map(\.x).min(), 0)
        XCTAssertEqual(opened.map(\.x).max(), 18)
        XCTAssertEqual(opened.map(\.y).min(), 0)
        XCTAssertEqual(opened.map(\.y).max(), 18)
        XCTAssertFalse(opened.contains { $0.x == 9 && $0.y == 9 })
    }

    func testCursorCApertureMotionIsPeriodicAndKeepsStaticFallbackClosed() {
        let duration = MacIslandCursorPixelMotion.cycleDuration

        XCTAssertEqual(MacIslandCursorPixelMotion.openness(at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(
            MacIslandCursorPixelMotion.openness(at: duration / 2),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(MacIslandCursorPixelMotion.separation(at: 0), 0)
        XCTAssertEqual(MacIslandCursorPixelMotion.separation(at: duration / 2), 1)
        XCTAssertEqual(
            MacIslandCursorPixelMotion.scale(at: 0),
            MacIslandCursorPixelMotion.minimumScale,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            MacIslandCursorPixelMotion.scale(at: duration / 2),
            MacIslandCursorPixelMotion.maximumScale,
            accuracy: 0.0001
        )
        XCTAssertEqual(MacIslandCursorPixelMotion.openness(at: .nan), 0)
        XCTAssertEqual(MacIslandCursorPixelMotion.separation(at: .nan), 0)
        XCTAssertEqual(
            MacIslandCursorPixelMotion.scale(at: .nan),
            MacIslandCursorPixelMotion.maximumScale,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            MacIslandCursorPixelMotion.openness(at: 0.31),
            MacIslandCursorPixelMotion.openness(at: 0.31 + duration),
            accuracy: 0.0001
        )
    }

    func testHookBoundaryDropsPromptOutputAndToolArguments() {
        let event = HookEvent(
            sessionId: "codex-hook",
            cwd: "/tmp/workspace",
            event: "PermissionRequest",
            status: "waiting_for_approval",
            provider: .codex,
            clientInfo: .codexCLI(),
            pid: 123,
            tty: "/dev/ttys001",
            tool: "Bash",
            toolInput: ["command": AnyCodable("sensitive command")],
            toolUseId: "tool-1",
            notificationType: nil,
            message: "full private prompt or output",
            bridgeIntervention: SessionIntervention(
                id: "intervention-1",
                kind: .approval,
                title: "Approval",
                message: "private details",
                options: [],
                questions: [],
                supportsSessionScope: false,
                metadata: [:]
            ),
            bridgeExpectsResponse: true
        )

        let safe = SessionMonitor.productSafeHookEvent(event)
        XCTAssertNil(safe.toolInput)
        XCTAssertNil(safe.message)
        XCTAssertNil(safe.bridgeIntervention)
        XCTAssertFalse(safe.expectsResponse)
        XCTAssertEqual(safe.tool, "Bash")
        guard case .waitingForApproval(let permission) = safe.sessionPhase else {
            return XCTFail("Expected a notification-only approval state")
        }
        XCTAssertEqual(permission.toolUseId, "tool-1")
        XCTAssertEqual(permission.toolName, "Bash")
        XCTAssertNil(permission.toolInput)
    }

    func testPermissionSocketNeverWaitsForIslandResponse() {
        XCTAssertFalse(
            HookSocketServer.shouldHoldSocketOpen(
                envelopeExpectsResponse: true,
                eventExpectsResponse: true
            ))
    }

    func testCodexMutatingAPIsAreBlockedBeforeNetworkAccess() async {
        let monitor = CodexAppServerMonitor.shared

        await assertMonitorOnly {
            _ = try await monitor.startThread(cwd: "/tmp/mac-island")
        }
        await assertMonitorOnly {
            _ = try await monitor.resumeThread(threadId: "thread-1")
        }
        await assertMonitorOnly {
            try await monitor.archiveThread(threadId: "thread-1")
        }
        await assertMonitorOnly {
            try await monitor.continueThread(
                threadId: "thread-1",
                expectedTurnId: "turn-1",
                text: "must not be sent"
            )
        }
        await assertMonitorOnly {
            try await monitor.submitRequestUserInputOutput(
                threadId: "thread-1",
                callId: "call-1",
                answers: ["scope": ["tests"]]
            )
        }
        let answered = await monitor.answer(threadId: "thread-1", answers: [:])
        XCTAssertFalse(answered)
    }

    private func observedSession(
        id: String,
        profileID: String,
        name: String,
        origin: String,
        source: String,
        kind: SessionClientKind = .custom
    ) -> SessionState {
        SessionState(
            sessionId: id,
            cwd: "/tmp/\(id)",
            provider: .claude,
            clientInfo: SessionClientInfo(
                kind: kind,
                profileID: profileID,
                name: name,
                origin: origin,
                threadSource: source
            )
        )
    }

    private func assertMonitorOnly(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected monitor-only control error", file: file, line: line)
        } catch MacIslandMonitorOnlyError.controlDisabled {
            // Expected: the guard runs before app-server connection or mutation.
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
