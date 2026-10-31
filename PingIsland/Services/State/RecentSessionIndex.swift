import Combine
import Foundation

enum RecentSessionRetention: String, CaseIterable, Identifiable, Codable, Sendable {
    case week, day, sessionOnly, disabled

    nonisolated static let settingsKey = "macIslandRecentSessionRetention"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: "7 天，最多 200 条"
        case .day: "24 小时，最多 100 条"
        case .sessionOnly: "仅本次运行"
        case .disabled: "不记录"
        }
    }
    nonisolated var capacity: Int { self == .day ? 100 : (self == .disabled ? 0 : 200) }
    nonisolated var maxAge: TimeInterval { self == .day ? 86_400 : 7 * 86_400 }
    nonisolated var persists: Bool { self == .week || self == .day }
}

/// Deliberate allowlist: no title, prompt, reply, tool body, URL query, PID or TTY.
/// Old process/terminal identities must not become launch targets after a reboot.
struct RecentSessionRecord: Codable, Equatable, Identifiable, Sendable {
    let sessionID: String
    let nativeSessionID: String
    let client: MacIslandClient
    let origin: String
    let workspace: String
    let lastActivity: Date

    nonisolated var id: String { "\(client.rawValue):\(origin):\(nativeSessionID)" }

    nonisolated init?(session: SessionState) {
        guard !session.isRemoteSession,
            session.linkedParentSessionId == nil,
            session.codexParentThreadId == nil,
            let snapshot = MacIslandSessionSnapshot.make(from: session)
        else { return nil }
        sessionID = session.sessionId
        nativeSessionID = SessionNavigationIdentity.nativeSessionID(for: session)
        client = snapshot.client
        let explicitOrigin = session.clientInfo.origin?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let explicitOrigin, !explicitOrigin.isEmpty {
            switch explicitOrigin {
            case "cli", "desktop", "web", "unknown": origin = explicitOrigin
            case "cursor-local" where snapshot.client == .cursor: origin = "desktop"
            case "native-runtime" where snapshot.client == .codexCLI: origin = "cli"
            default: origin = "unknown"
            }
        } else {
            switch snapshot.client {
            case .codexCLI: origin = "cli"
            case .codexDesktop, .cursor: origin = "desktop"
            case .claudeCode:
                origin = session.clientInfo.profileID == "claude-desktop-code" ? "desktop" : "cli"
            case .openCode, .hermes, .dsh: origin = "unknown"
            }
        }
        workspace = session.cwd
        lastActivity = session.lastActivity
    }

    nonisolated init(
        sessionID: String, nativeSessionID: String, client: MacIslandClient,
        origin: String, workspace: String, lastActivity: Date
    ) {
        self.sessionID = sessionID
        self.nativeSessionID = nativeSessionID
        self.client = client
        self.origin = origin
        self.workspace = workspace
        self.lastActivity = lastActivity
    }

    nonisolated func isValid(at now: Date) -> Bool {
        !sessionID.isEmpty && sessionID.utf8.count <= 1_024
            && !nativeSessionID.isEmpty && nativeSessionID.utf8.count <= 1_024
            && workspace.hasPrefix("/") && workspace.utf8.count <= 4_096
            && !workspace.contains("\0") && !nativeSessionID.contains("\0")
            && ["cli", "desktop", "web", "unknown"].contains(origin)
            && lastActivity.timeIntervalSince1970.isFinite
            && lastActivity <= now.addingTimeInterval(60)
    }

    var clientName: String {
        switch client {
        case .codexCLI: "Codex CLI"
        case .codexDesktop: "Codex"
        case .cursor: "Cursor"
        case .claudeCode: origin == "desktop" ? "Claude Desktop · Code" : "Claude Code"
        case .openCode: "OpenCode"
        case .hermes: origin == "desktop" ? "Hermes Desktop" : "Hermes"
        case .dsh: "DeepSeek Harness"
        }
    }

    /// Reconstitute routing metadata only. Navigation must still report its
    /// actual evidence, and continuation revalidates binaries and directories.
    var navigationSession: SessionState {
        let provider: SessionProvider = client == .codexCLI || client == .codexDesktop ? .codex : .claude
        var info = SessionClientInfo.default(for: provider)
        switch client {
        case .codexCLI:
            info.kind = .codexCLI
            info.bundleIdentifier = nil
        case .codexDesktop:
            info.bundleIdentifier = "com.openai.codex"
        case .cursor:
            info.kind = .claudeCode
            info.profileID = "cursor"
            info.bundleIdentifier = "com.todesktop.230313mzl4w4u92"
        case .claudeCode:
            info.kind = .claudeCode
            info.profileID = origin == "desktop" ? "claude-desktop-code" : "claude-code"
            info.bundleIdentifier = origin == "desktop" ? "com.anthropic.claudefordesktop" : nil
        case .openCode:
            info.kind = .custom
            info.profileID = "opencode"
            info.bundleIdentifier = origin == "desktop" ? "ai.opencode.desktop" : nil
        case .hermes:
            info.kind = .custom
            info.profileID = "hermes"
            info.bundleIdentifier = origin == "desktop" ? "com.nousresearch.hermes.setup" : nil
        case .dsh:
            info.kind = .custom
            info.profileID = "dsh"
            info.bundleIdentifier = nil
        }
        info.name = clientName
        info.origin = origin
        info.threadSource = client == .openCode && origin == "unknown" ? "opencode-recovery" : "recent-metadata"
        // Never reuse an arbitrary URL from stored content or a default client.
        info.launchURL = nil
        if origin != "unknown", client == .codexDesktop || client == .cursor,
            let bundle = info.bundleIdentifier
        {
            info.launchURL = SessionClientInfo.appLaunchURL(
                bundleIdentifier: bundle, sessionId: nativeSessionID, workspacePath: workspace
            )
        }
        let routingID = MacIslandProductPolicy.observedSessionKey(nativeSessionID: nativeSessionID, clientInfo: info)
        return SessionState(
            sessionId: routingID, cwd: workspace, provider: provider,
            clientInfo: info, ingress: .desktopAppMonitor,
            suppressInAppPromptControls: true, phase: .idle,
            lastActivity: lastActivity, createdAt: lastActivity)
    }
}

@MainActor
final class RecentSessionIndex: ObservableObject {
    // No actor-bound teardown: avoid the older Swift isolated-deinit runtime bug
    // during synchronous release, as covered by the index lifetime tests.
    nonisolated deinit {}

    static let shared: RecentSessionIndex = {
        let isolated = !MacIslandRuntimeEnvironment.allowsLiveIO
        let index = RecentSessionIndex(
            fileURL: isolated ? nil : defaultFileURL,
            retention: isolated ? .sessionOnly : AppSettings.shared.recentSessionRetention
        )
        if !isolated {
            index.retentionSubscription = AppSettings.shared.$recentSessionRetention
                .dropFirst()
                .sink { [weak index] value in index?.setRetention(value) }
        }
        return index
    }()

    @Published private(set) var records: [RecentSessionRecord] = []
    @Published private(set) var retention: RecentSessionRetention
    @Published private(set) var storageMessage: String?
    private let fileURL: URL?
    private let now: () -> Date
    private var clearedBefore: Date?
    private var saveTask: Task<Void, Never>?
    private var retentionSubscription: AnyCancellable?

    private struct Envelope: Codable {
        let version: Int
        let clearedBefore: Date?
        let records: [RecentSessionRecord]
    }

    private static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MacIsland/recent-sessions-v1.json")
    }

    init(fileURL: URL?, retention: RecentSessionRetention = .week, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.retention = retention
        self.now = now
        guard retention.persists else {
            removeFile()
            return
        }
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 1_500_000 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: fileURL))
            guard envelope.version == 1, envelope.records.count <= 200 else { throw CocoaError(.fileReadCorruptFile) }
            // Observations tolerate up to 60 seconds of clock skew. Preserve
            // a legitimate future watermark across relaunch for the same reason.
            clearedBefore = envelope.clearedBefore.map { min($0, now().addingTimeInterval(60)) }
            records = pruned(envelope.records)
            persistNow()
        } catch {
            records = []
            storageMessage = "最近会话索引无法读取，已从空列表继续。"
        }
    }

    func observe(_ sessions: [SessionState]) {
        ingest(sessions.compactMap(RecentSessionRecord.init(session:)))
    }

    func ingest(_ candidates: [RecentSessionRecord]) {
        guard retention != .disabled else { return }
        let next = pruned(records + candidates)
        guard next != records else { return }
        records = next
        scheduleSave()
    }

    func prune() {
        let next = pruned(records)
        guard next != records else { return }
        records = next
        scheduleSave()
    }

    func setRetention(_ value: RecentSessionRetention) {
        guard retention != value else { return }
        saveTask?.cancel()
        saveTask = nil
        if retention == .disabled {
            // Re-enabling starts a new recording window, not a re-import of
            // unchanged metadata accumulated while recording was off.
            advanceClearWatermark()
        }
        retention = value
        if value == .disabled {
            advanceClearWatermark()
            records = []
        } else {
            records = pruned(records)
        }
        if value.persists { persistNow() } else { removeFile() }
    }

    func clear() {
        saveTask?.cancel()
        saveTask = nil
        advanceClearWatermark()
        records = []
        // Keep only the cutoff so unchanged native history cannot immediately
        // repopulate a list the user just cleared. Native databases are untouched.
        if retention.persists { persistNow() } else { removeFile() }
    }

    private func advanceClearWatermark() {
        // A source clock can be slightly ahead. Clearing must also reject the
        // unchanged records we already accepted, including those future dates.
        clearedBefore = max(now(), clearedBefore ?? .distantPast, records.map(\.lastActivity).max() ?? .distantPast)
    }

    private func pruned(_ source: [RecentSessionRecord]) -> [RecentSessionRecord] {
        let date = now()
        let cutoff = date.addingTimeInterval(-retention.maxAge)
        var latest: [String: RecentSessionRecord] = [:]
        for record in source
        where record.isValid(at: date)
            && record.lastActivity >= cutoff
            && (clearedBefore == nil || record.lastActivity > clearedBefore!)
        {
            if let existing = latest[record.id], existing.lastActivity >= record.lastActivity { continue }
            latest[record.id] = record
        }
        // An authoritative origin replaces only an unresolved metadata row.
        let resolved = Set(
            latest.values.filter { $0.origin != "unknown" }.map { "\($0.client.rawValue):\($0.nativeSessionID)" })
        let ordered = latest.values.filter {
            $0.origin != "unknown" || !resolved.contains("\($0.client.rawValue):\($0.nativeSessionID)")
        }.sorted { $0.lastActivity == $1.lastActivity ? $0.id < $1.id : $0.lastActivity > $1.lastActivity }
        return Array(ordered.prefix(retention.capacity))
    }

    private func scheduleSave() {
        guard retention.persists else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    /// Also used by deterministic tests instead of waiting for the debounce.
    func persistNow() {
        guard retention.persists, let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(Envelope(version: 1, clearedBefore: clearedBefore, records: records))
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            storageMessage = nil
        } catch {
            storageMessage = "最近会话暂时无法保存；本次运行仍可使用。"
        }
    }

    private func removeFile() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
            storageMessage = nil
        } catch {
            storageMessage = "最近会话索引文件未能移除，请检查文件权限。"
        }
    }
}
