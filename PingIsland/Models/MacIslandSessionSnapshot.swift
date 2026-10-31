import Foundation

enum MacIslandClient: String, Codable, Equatable, Sendable {
    case codexCLI
    case codexDesktop
    case cursor
    case claudeCode
    case openCode
    case hermes
    case dsh
}

enum MacIslandSessionStatus: String, Codable, Sendable {
    case idle
    case working
    case needsAttention
    case completed
    case error
    case stale
}

enum MacIslandMonitorSource: String, Codable, Sendable {
    case codexAppServer
    case hook
    case transcript
    case process
}

enum MacIslandSessionHealth: String, Codable, Sendable {
    case healthy
    case degraded
    case stale
}

struct MacIslandJumpTarget: Codable, Equatable, Sendable {
    let launchURL: String?
    let bundleIdentifier: String?
    let workspace: String
    let terminalBundleIdentifier: String?
    let terminalSessionIdentifier: String?
}

/// Stable, minimal projection consumed by Mac Island surfaces.
///
/// Full prompts and outputs are intentionally absent. The upstream SessionState
/// remains the internal state-machine record, while this value is the product
/// boundary exposed to V1 UI and fixtures.
struct MacIslandSessionSnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let client: MacIslandClient
    let workspace: String
    let title: String
    let status: MacIslandSessionStatus
    let lastActivity: Date
    let source: MacIslandMonitorSource
    let health: MacIslandSessionHealth
    let jumpTarget: MacIslandJumpTarget

    nonisolated static func make(
        from session: SessionState,
        now: Date = Date()
    ) -> MacIslandSessionSnapshot? {
        guard
            MacIslandProductPolicy.supportsSession(
                provider: session.provider,
                clientInfo: session.clientInfo
            )
        else { return nil }

        let age = max(0, now.timeIntervalSince(session.lastActivity))
        let health: MacIslandSessionHealth =
            if age >= 300 {
                .stale
            } else if age >= 10 {
                .degraded
            } else {
                .healthy
            }

        let status: MacIslandSessionStatus
        if age >= 300 {
            status = .stale
        } else if !session.completedErrorToolIDs.isEmpty {
            status = .error
        } else if session.needsAttention {
            status = .needsAttention
        } else {
            status =
                switch session.phase {
                case .processing, .compacting: .working
                case .ended: .completed
                case .idle, .waitingForInput, .waitingForApproval: .idle
                }
        }

        let client: MacIslandClient
        if session.clientInfo.isDSHClient {
            client = .dsh
        } else if session.clientInfo.isOpenCodeClient {
            client = .openCode
        } else if session.clientInfo.isHermesClient {
            client = .hermes
        } else if session.clientInfo.isClaudeCodeClient {
            client = .claudeCode
        } else if session.clientInfo.profileID == "cursor"
            || session.clientInfo.profileID == "cursor-hooks"
            || session.clientInfo.profileID == "cursor-extension"
            || session.clientInfo.name?.localizedCaseInsensitiveContains("Cursor") == true
        {
            client = .cursor
        } else if session.clientInfo.kind == .codexCLI {
            client = .codexCLI
        } else {
            client = .codexDesktop
        }

        let source: MacIslandMonitorSource =
            switch session.ingress {
            case .codexAppServer: .codexAppServer
            case .hookBridge, .remoteBridge: .hook
            case .desktopAppMonitor: .transcript
            case .nativeRuntime: .process
            }

        return MacIslandSessionSnapshot(
            id: session.sessionId,
            client: client,
            workspace: session.cwd,
            title: MacIslandProductPolicy.contentDerivedTitlesEnabled
                ? session.displayTitle
                : MacIslandProductPolicy.privacySafeSessionTitle(
                    providerDisplayName: session.providerDisplayName
                ),
            status: status,
            lastActivity: session.lastActivity,
            source: source,
            health: health,
            jumpTarget: MacIslandJumpTarget(
                launchURL: session.clientInfo.launchURL,
                bundleIdentifier: session.clientInfo.bundleIdentifier,
                workspace: session.cwd,
                terminalBundleIdentifier: session.clientInfo.terminalBundleIdentifier,
                terminalSessionIdentifier: session.clientInfo.terminalSessionIdentifier
            )
        )
    }

    nonisolated static func sorted(_ snapshots: [MacIslandSessionSnapshot]) -> [MacIslandSessionSnapshot] {
        snapshots.sorted { lhs, rhs in
            let lhsPriority = priority(lhs.status)
            let rhsPriority = priority(rhs.status)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            return lhs.lastActivity > rhs.lastActivity
        }
    }

    private nonisolated static func priority(_ status: MacIslandSessionStatus) -> Int {
        switch status {
        case .needsAttention: 0
        case .error: 1
        case .working: 2
        case .completed: 3
        case .idle: 4
        case .stale: 5
        }
    }
}
