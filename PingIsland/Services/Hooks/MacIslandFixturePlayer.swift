import Foundation

enum MacIslandFixturePlayer {
    nonisolated static let environmentKey = "MAC_ISLAND_FIXTURE_PATH"

    /// Presentation-only controls for real window screenshots with synthetic data.
    static func preparePresentation(environment: [String: String] = Foundation.ProcessInfo.processInfo.environment) {
        guard !(environment[environmentKey] ?? "").isEmpty,
            !MacIslandRuntimeEnvironment.allowsLiveIO
        else { return }
        if let language = environment["MAC_ISLAND_FIXTURE_LANGUAGE"].flatMap(AppLanguage.init(rawValue:)) {
            AppSettings.shared.appLanguage = language
        }
        if let mode = environment["MAC_ISLAND_FIXTURE_SURFACE"].flatMap(IslandSurfaceMode.init(rawValue:)) {
            AppSettings.surfaceMode = mode
        }
        ScreenPrivacyStore.shared.mode = .titles
    }

    private struct Document: Decodable {
        let schemaVersion: Int
        let events: [FixtureEvent]
        let storedCodexThreads: [StoredCodexThread]?
        let personalAgents: [PersonalAgentFixture]?
    }

    private struct PersonalAgentFixture: Decodable {
        let client: String
        let agentName: String?
        let activityLabels: [String]?
    }

    /// Explicit synthetic fixture files are the only file-backed source for
    /// these UI previews. Production observations are never encoded or saved.
    static func personalAgentObservations(fileURL: URL) throws -> [PersonalAgentObservation] {
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
        guard document.schemaVersion == 1 else { throw FixtureError.unsupportedSchema(document.schemaVersion) }
        var rows: [PersonalAgentObservation] = []
        for fixture in document.personalAgents ?? [] {
            guard let client = PersonalAgentClient(rawValue: fixture.client) else {
                throw FixtureError.unsupportedClient(fixture.client)
            }
            let window: PersonalAgentAXNode
            switch client {
            case .grokBot:
                window = .init(
                    role: "AXWindow",
                    children: [
                        .init(
                            role: "AXButton", label: "View conversation details",
                            children: [
                                .init(role: "AXStaticText", label: fixture.agentName ?? "")
                            ])
                    ])
            case .muse:
                window = .init(
                    role: "AXWindow",
                    children: [
                        .init(role: "AXImage", label: "Muse avatar"),
                        .init(role: "AXPopUpButton", label: "Edit avatar and name"),
                        .init(role: "AXStaticText", label: fixture.agentName.map { "\($0) Connected" } ?? ""),
                        .init(role: "AXCheckBox", label: "Activity", selected: true),
                        .init(role: "AXCheckBox", label: "Approvals"),
                        .init(role: "AXCheckBox", label: "Upcoming"),
                        .init(role: "AXCheckBox", label: "Identity"),
                        .init(role: "AXHeading", label: "Today"),
                    ] + (fixture.activityLabels ?? []).map { .init(role: "AXButton", label: $0) })
            case .dot: continue
            }
            // Existing playback fixtures describe the verified original layouts.
            rows += PersonalAgentAdapter.observations(
                client: client, version: client == .muse ? "4.1" : "0.68.1",
                windows: [window], observedAt: Date(), epoch: UInt64(rows.count))
        }
        return rows
    }

    private struct FixtureEvent: Decodable {
        let delayMilliseconds: Int?
        let sessionId: String
        let client: String
        let workspace: String
        let event: String
        let status: String
        let message: String?
        let tool: String?
        let toolUseId: String?
        let nativeTitle: String?
    }

    private struct StoredCodexThread: Decodable {
        let sessionId: String
        let workspace: String
        let nativeTitle: String?
        let preview: String?
        let activitySecondsAgo: Double
    }

    enum FixtureError: LocalizedError {
        case unsupportedSchema(Int)
        case unsupportedClient(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let version):
                "Unsupported Mac Island fixture schema: \(version)"
            case .unsupportedClient(let client):
                "Unsupported Mac Island fixture client: \(client)"
            }
        }
    }

    static func play(fileURL: URL) async throws {
        let data = try Data(contentsOf: fileURL)
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1 else {
            throw FixtureError.unsupportedSchema(document.schemaVersion)
        }

        // Synthetic metadata for deterministic current/history UI acceptance.
        // Fixture launch already disables all real monitors and index storage.
        for thread in document.storedCodexThreads ?? [] {
            let activityAt = Date().addingTimeInterval(-max(0, thread.activitySecondsAgo))
            await SessionStore.shared.upsertCodexSession(
                sessionId: thread.sessionId, name: thread.nativeTitle, preview: thread.preview,
                cwd: thread.workspace, phase: .idle, intervention: nil,
                clientInfo: .codexApp(threadId: thread.sessionId),
                createdAt: activityAt, activityAt: activityAt, allowSyntheticActivityTimestamp: false
            )
        }

        for fixture in document.events {
            if let delay = fixture.delayMilliseconds, delay > 0 {
                try await Task.sleep(for: .milliseconds(delay))
            }
            await SessionStore.shared.process(.hookReceived(try makeHookEvent(from: fixture)))
        }
    }

    private static func makeHookEvent(from fixture: FixtureEvent) throws -> HookEvent {
        let provider: SessionProvider
        let clientInfo: SessionClientInfo

        switch fixture.client {
        case "codex-cli":
            provider = .codex
            clientInfo = .codexCLI()
        case "codex-desktop":
            provider = .codex
            clientInfo = .codexApp(threadId: fixture.sessionId)
        case "cursor":
            provider = .claude
            clientInfo = SessionClientInfo(
                kind: .custom,
                profileID: "cursor-hooks",
                name: "Cursor",
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                origin: "ide"
            )
        default:
            throw FixtureError.unsupportedClient(fixture.client)
        }

        return HookEvent(
            sessionId: fixture.sessionId,
            cwd: fixture.workspace,
            event: fixture.event,
            status: fixture.status,
            provider: provider,
            clientInfo: clientInfo,
            pid: nil,
            tty: nil,
            tool: fixture.tool,
            toolInput: nil,
            toolUseId: fixture.toolUseId,
            notificationType: nil,
            message: fixture.message,
            nativeTitle: fixture.nativeTitle
        )
    }
}
