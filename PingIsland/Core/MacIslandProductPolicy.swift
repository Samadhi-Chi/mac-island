import CoreGraphics
import Foundation

enum MacIslandClientKind: String, Codable, Equatable, Sendable {
    case claudeCode
    case openCode
    case hermes
    case dsh
}

enum MacIslandSessionOrigin: String, Codable, Equatable, Sendable {
    case cli
    case desktop
    /// Metadata recovery cannot infer the owning surface from a running app.
    case unknown
    /// Local browser surface served by a desktop agent runtime such as DSH.
    case web
}

struct MacIslandObservedEventV1: Equatable, Sendable {
    let sessionID: String
    let client: MacIslandClientKind
    let origin: MacIslandSessionOrigin
    let project: String
    let nativeTitle: String?
    let provider: String?
    let model: String?
    let status: String
    let displayText: String?
    let toolName: String?
    let timestamp: Date
}

struct MacIslandActivityItem: Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case toolStarted
        case toolCompleted
        case toolFailed
        case needsPermission
        case subagentStarted
        case subagentStopped
        case taskCreated
        case taskCompleted
        case turnCompleted
    }

    let kind: Kind
    let title: String
    let timestamp: Date
}

/// Product-level constraints for the first runnable Mac Island development build.
///
/// Keep these guarantees centralized so a dormant upstream feature cannot become
/// reachable merely because a view or service is re-enabled during an upstream merge.
enum MacIslandProductPolicy {
    /// Experimental UI metadata observations are independent of hook clients.
    /// Dot is app-entry-only until an independent task source is verified.
    nonisolated static let personalAgentInterfaceClients: Set<PersonalAgentClient> = [.muse, .grokBot]
    nonisolated static let displayName = "Mac Island"

    nonisolated static func resolvedRuntimeBundleIdentifier(
        _ bundleIdentifier: String?
    ) -> String {
        bundleIdentifier ?? "local.shared.macisland"
    }

    /// Runtime identity follows the active shared-user xcconfig. Source code,
    /// log labels, and single-instance checks must not pin either local user.
    nonisolated static var runtimeBundleIdentifier: String {
        resolvedRuntimeBundleIdentifier(Bundle.main.bundleIdentifier)
    }

    nonisolated static var loggingSubsystem: String {
        runtimeBundleIdentifier
    }

    /// V1 observes attention requests and routes the user back to the originating
    /// client. It never approves, rejects, answers, or sends agent input.
    nonisolated static let monitorOnly = true

    /// Development builds are deliberately local-only. Update and analytics code
    /// remains available for upstream merging but is never started by this product.
    nonisolated static let analyticsEnabled = false
    nonisolated static let updatesEnabled = false
    nonisolated static let automaticallyInstallsHooks = false
    nonisolated static let mascotsEnabled = false
    /// This product is deliberately silent. Playback is blocked at the shared
    /// audio boundary as well as in persisted defaults.
    nonisolated static let soundsEnabled = false
    /// Session lifecycle events may update the compact indicator, but must never
    /// expand the Island on their own. Detail is revealed only by a deliberate
    /// pointer interaction (hover or click).
    nonisolated static let automaticPanelPresentationEnabled = false
    /// Completion/attention transitions should not resize or bounce the compact
    /// Island while the user is working in another app.
    nonisolated static let ambientAttentionMotionEnabled = false
    /// Usage is derived locally from rate-limit events and projected down to
    /// provider/window/remaining quota before it reaches the UI or cache.
    nonisolated static let usageTrackingEnabled = true
    nonisolated static let hookPayloadLoggingEnabled = false
    nonisolated static let brandedClientAssetsEnabled = false

    /// Persisted once so existing installs receive this preset while later
    /// user adjustments remain respected.
    nonisolated static let configurationDefaultsVersion = 3
    nonisolated static let defaultContentFontSize: Double = 12
    nonisolated static let defaultCompletionCardHeight: Double = 90
    nonisolated static let defaultMaximumPanelHeight: Double = 560
    nonisolated static let defaultMaximumPanelWidth: Double = 640

    /// Keep persisted and diagnostic projections content-free even though the
    /// user explicitly wants rich, local, on-screen execution detail.
    nonisolated static let privacyShieldEnabled = true
    nonisolated static let contentDerivedTitlesEnabled = false
    nonisolated static let conversationPreviewsEnabled = false
    /// Full turns may be read from the local, read-only Codex app-server for
    /// in-memory presentation. They never cross into persisted product snapshots,
    /// usage caches, diagnostics, Bridge logs, or telemetry.
    nonisolated static let localConversationTurnsEnabled = true
    /// Fresh installs expose native titles only. Existing installations migrate
    /// their prior rich presentation once; the user can then choose any level.
    nonisolated static let defaultScreenContentVisibility: ScreenContentVisibility = .titles
    /// Legacy rich-view capabilities. ScreenPrivacyStore gates every surface and
    /// route dynamically; these constants never override that user preference.
    nonisolated static let onScreenPrivacyShieldEnabled = false
    nonisolated static let conversationDetailsVisibleByDefault = true
    /// The user explicitly opted into a project + thread title in the local UI.
    /// The thread component remains in memory and is still excluded from the
    /// persisted association, diagnostics, usage cache, Bridge logs, and telemetry.
    nonisolated static let localProjectAndThreadTitlesEnabled = true
    /// The user explicitly opted into screenshot-style detail. Content is shown
    /// only from the in-memory local session snapshot; it is never copied into
    /// usage caches, diagnostics, telemetry, or Bridge logs.
    nonisolated static let localConversationDetailsEnabled = true

    nonisolated static func privacySafeSessionTitle(providerDisplayName: String) -> String {
        providerDisplayName
    }

    nonisolated static let supportedManagedHookProfileIDs: Set<String> = [
        "claude-hooks",
        "codex-hooks",
        "cursor-hooks",
        "opencode-hooks",
        "hermes-hooks",
        "dsh-hooks",
    ]

    nonisolated static let supportedIDEExtensionProfileIDs: Set<String> = [
        "cursor-extension"
    ]

    nonisolated static func supportsManagedHookProfile(id: String) -> Bool {
        supportedManagedHookProfileIDs.contains(id)
    }

    nonisolated static func supportsIDEExtensionProfile(id: String) -> Bool {
        supportedIDEExtensionProfileIDs.contains(id)
    }

    /// Mac Island accepts only the explicitly supported local monitoring clients.
    /// Generic Claude Desktop chat, Cowork, web sessions, gateway jobs, cron jobs,
    /// and unrelated Claude-compatible hook consumers stay outside the boundary.
    nonisolated static func supportsSession(
        provider: SessionProvider,
        clientInfo: SessionClientInfo
    ) -> Bool {
        if provider == .codex { return true }
        if isCursorClient(clientInfo) { return true }
        guard provider == .claude else { return false }

        if clientInfo.isDSHClient {
            return isInteractiveOrigin(clientInfo.origin)
                || clientInfo.origin?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    == MacIslandSessionOrigin.web.rawValue
        }

        if clientInfo.isOpenCodeClient || clientInfo.isHermesClient {
            return isInteractiveOrigin(clientInfo.origin)
                || clientInfo.isUnknownOpenCodeRecovery
        }

        if clientInfo.isClaudeCodeClient {
            return isInteractiveOrigin(clientInfo.origin)
        }

        return false
    }

    nonisolated static func isInteractiveOrigin(_ origin: String?) -> Bool {
        guard
            let normalized = origin?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(), !normalized.isEmpty
        else {
            // Older Claude Code hook payloads do not include an origin. They
            // are still local CLI observations; explicit non-interactive
            // origins (cron/gateway/web) remain rejected below.
            return true
        }
        return normalized == MacIslandSessionOrigin.cli.rawValue
            || normalized == MacIslandSessionOrigin.desktop.rawValue
    }

    nonisolated static func isCursorClient(_ clientInfo: SessionClientInfo) -> Bool {
        let cursorBundleIdentifier = "com.todesktop.230313mzl4w4u92"
        return clientInfo.profileID == "cursor"
            || clientInfo.profileID == "cursor-local"
            || clientInfo.profileID == "cursor-hooks"
            || clientInfo.profileID == "cursor-extension"
            || clientInfo.bundleIdentifier == cursorBundleIdentifier
            || clientInfo.bundleIdentifier == "\(cursorBundleIdentifier).helper"
            || clientInfo.name?.localizedCaseInsensitiveContains("Cursor") == true
    }

    /// Stable in-memory identity for hook clients whose native IDs can overlap
    /// across products or between CLI and desktop runtimes.
    nonisolated static func observedSessionKey(
        nativeSessionID: String,
        clientInfo: SessionClientInfo
    ) -> String {
        guard
            clientInfo.isClaudeCodeClient
                || clientInfo.isOpenCodeClient
                || clientInfo.isHermesClient
                || clientInfo.isDSHClient
        else {
            return nativeSessionID
        }
        let client =
            clientInfo.profileID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "claude-code"
        let origin =
            clientInfo.origin?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? MacIslandSessionOrigin.cli.rawValue
        return "observed:\(client):\(origin):\(nativeSessionID)"
    }
}

/// Presentation constants for the clean-room Mac Island surface.
///
/// These values describe timing and density only. They are derived from our own
/// interaction tests and keep the implementation independent from third-party
/// code and assets.
enum MacIslandPresentationPolicy {
    nonisolated static let preferredPanelWidth: CGFloat = 600
    nonisolated static let openedDecorationWidth: CGFloat = 62
    nonisolated static let expandedConversationCardHeight: CGFloat = 156
    nonisolated static let conversationDetailCharacterLimit = 1_600
    nonisolated static let conversationActivityCharacterLimit = 240
    /// Keep the AppKit surface local to the Island. A screen-wide transparent
    /// high-level window corrupts Notification Center's backdrop sampling.
    nonisolated static let dockedWindowHorizontalChrome: CGFloat = 96
    nonisolated static let dockedWindowVerticalChrome: CGFloat = 64
    nonisolated static let panelHoverOpenDelay: TimeInterval = 0.13
    nonisolated static let panelHoverCloseDelay: TimeInterval = 0.20
    nonisolated static let rowDetailOpenDelay: TimeInterval = 0.09
    nonisolated static let rowDetailCloseDelay: TimeInterval = 0.18
    nonisolated static let rowDetailAnimationDuration: TimeInterval = 0.19

    nonisolated static func sessionListRowMinimumHeight(for session: SessionState) -> CGFloat {
        if session.needsManualAttention { return 86 }
        return session.phase.isActive ? 74 : 64
    }

    /// The collapsed Island's client glyph is a live-work indicator, not a
    /// persistent brand mark. Idle, completed, and attention-only sessions keep
    /// the leading slot empty; the right-side attention indicator remains
    /// independent.
    nonisolated static func shouldShowClosedClientGlyph(
        for phase: SessionPhase?
    ) -> Bool {
        phase?.isActive == true
    }

    nonisolated static func shouldUseScrollContainer(sessionCount: Int) -> Bool {
        sessionCount > 3
    }

    /// Conversation text is a separate user choice from upstream Agent/subagent
    /// activity details. Turning off the latter must not hide Mac Island's local
    /// user/assistant progress card.
    nonisolated static func conversationDetailsEnabled(
        agentActivityDetailsEnabled: Bool
    ) -> Bool {
        if MacIslandProductPolicy.monitorOnly {
            return MacIslandProductPolicy.localConversationDetailsEnabled
        }
        return agentActivityDetailsEnabled
    }

    nonisolated static func dockedWindowFrame(in screenFrame: CGRect) -> CGRect {
        let targetWidth = preferredPanelWidth + dockedWindowHorizontalChrome
        let targetHeight =
            CGFloat(MacIslandProductPolicy.defaultMaximumPanelHeight)
            + dockedWindowVerticalChrome
        let width = min(screenFrame.width, targetWidth)
        let height = min(screenFrame.height, targetHeight)

        return CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    nonisolated static func shouldShowConversationDetail(
        isExpanded: Bool,
        detailsEnabled: Bool,
        usesTitleOnlyPresentation: Bool
    ) -> Bool {
        isExpanded && detailsEnabled && !usesTitleOnlyPresentation
    }

    nonisolated static func shouldShowInlineConversationPreview(
        isExpanded: Bool,
        usesMinimalCompactPresentation: Bool
    ) -> Bool {
        if MacIslandProductPolicy.monitorOnly {
            return MacIslandProductPolicy.conversationDetailsVisibleByDefault || isExpanded
        }
        return !usesMinimalCompactPresentation || isExpanded
    }

    nonisolated static func shouldBecomeKey(openReason: NotchOpenReason) -> Bool {
        if MacIslandProductPolicy.monitorOnly {
            switch openReason {
            case .click:
                return true
            case .hover, .notification, .boot, .unknown:
                return false
            }
        }

        switch openReason {
        case .notification:
            return false
        case .click, .hover, .boot, .unknown:
            return true
        }
    }
}

enum MacIslandMonitorOnlyError: LocalizedError {
    case controlDisabled

    var errorDescription: String? {
        "Mac Island is monitor-only. Continue in Codex or Cursor."
    }
}
