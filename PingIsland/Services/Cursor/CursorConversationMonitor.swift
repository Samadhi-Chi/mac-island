import Darwin
import Foundation
import os.log

struct CursorConversationSnapshot: Equatable, Sendable {
    let composerId: String
    let cwd: String
    let threadName: String
    let modelName: String?
    let phase: SessionPhase
    let historyItems: [ChatHistoryItem]
    let conversationInfo: ConversationInfo
    let createdAt: Date
    let updatedAt: Date
}

enum CursorConversationParser {
    nonisolated static func parse(
        composerId: String,
        workspaceId: String?,
        createdAtMilliseconds: Int64,
        updatedAtMilliseconds: Int64,
        headerJSON: String,
        composerJSON: String?,
        fallbackWorkspacePath: String?,
        bubbleJSONByID: [String: String] = [:]
    ) -> CursorConversationSnapshot? {
        guard composerId != "empty-state-draft",
            let header = jsonObject(headerJSON)
        else {
            return nil
        }

        let composer = composerJSON.flatMap(jsonObject) ?? [:]
        guard !boolValue(header["isArchived"]),
            !boolValue(header["isDraft"]),
            !boolValue(composer["isDraft"])
        else {
            return nil
        }

        guard
            let cwd = workspacePath(in: composer)
                ?? workspacePath(in: header)
                ?? normalizedWorkspacePath(fallbackWorkspacePath),
            cwd != "/"
        else {
            return nil
        }

        let threadName =
            normalizedText(header["name"])
            ?? normalizedText(composer["name"])
            ?? URL(fileURLWithPath: cwd).lastPathComponent
        guard !threadName.isEmpty else { return nil }

        let createdAt = date(
            milliseconds: int64Value(header["createdAt"])
                ?? int64Value(composer["createdAt"])
                ?? createdAtMilliseconds
        )
        let updatedAt = date(
            milliseconds: int64Value(header["lastUpdatedAt"])
                ?? int64Value(composer["lastUpdatedAt"])
                ?? updatedAtMilliseconds
        )

        let composerStatus = normalizedText(composer["status"])?.lowercased()
        let phase = phase(header: header, composer: composer)
        let historyItems = parsedHistoryItems(
            from: composer,
            bubbleJSONByID: bubbleJSONByID,
            phase: phase,
            composerStatus: composerStatus
        )
        let firstUser = historyItems.compactMap { item -> String? in
            if case .user(let text) = item.type { return text }
            return nil
        }.first
        let latestUser = historyItems.reversed().first { item in
            if case .user = item.type { return true }
            return false
        }
        let latestNarrative = historyItems.reversed().compactMap { item -> (text: String, role: String)? in
            switch item.type {
            case .user(let text): (text, "user")
            case .assistant(let text), .thinking(let text): (text, "assistant")
            case .toolCall, .interrupted: nil
            }
        }.first
        let latestToolName = historyItems.reversed().compactMap { item -> String? in
            if case .toolCall(let tool) = item.type { return tool.name }
            return nil
        }.first
        let conversationInfo = ConversationInfo(
            summary: threadName,
            lastMessage: latestNarrative?.text,
            lastMessageRole: latestNarrative?.role,
            lastToolName: latestToolName,
            firstUserMessage: firstUser,
            lastUserMessageDate: latestUser?.timestamp
        )

        return CursorConversationSnapshot(
            composerId: composerId,
            cwd: cwd,
            threadName: threadName,
            modelName: normalizedText(dictionary(composer["modelConfig"])?["modelName"]),
            phase: phase,
            historyItems: historyItems,
            conversationInfo: conversationInfo,
            createdAt: createdAt,
            updatedAt: max(updatedAt, historyItems.last?.timestamp ?? updatedAt)
        )
    }

    /// Cursor keeps the lightweight row headers in `composerData:*`, while the
    /// full local execution stream lives in separate `bubbleId:*` records. Read
    /// both so the Island can show thinking and tool progress instead of a single
    /// stale text preview. Nothing from these records is persisted by Mac Island.
    private nonisolated static func parsedHistoryItems(
        from composer: [String: Any],
        bubbleJSONByID: [String: String],
        phase: SessionPhase,
        composerStatus: String?
    ) -> [ChatHistoryItem] {
        guard let headers = composer["fullConversationHeadersOnly"] as? [[String: Any]] else {
            return []
        }

        return headers.suffix(64).compactMap { header in
            guard let type = intValue(header["type"]), type == 1 || type == 2,
                let id = normalizedText(header["bubbleId"])
            else {
                return nil
            }

            let bubble = bubbleJSONByID[id].flatMap(jsonObject)
            let groupingPreview = dictionary(header["grouping"])
                .flatMap { normalizedText($0["textPreview"]) }
            let timestamp =
                iso8601Date(bubble?["createdAt"])
                ?? iso8601Date(header["createdAt"])
                ?? .distantPast

            if type == 1 {
                guard
                    let text = normalizedText(bubble?["text"])
                        ?? normalizedText(bubble?["richText"])
                        ?? groupingPreview
                else {
                    return nil
                }
                return ChatHistoryItem(
                    id: "cursor-\(id)",
                    type: .user(text),
                    timestamp: timestamp
                )
            }

            if let tool = parsedToolCall(
                from: bubble,
                phase: phase,
                composerStatus: composerStatus
            ) {
                return ChatHistoryItem(
                    id: "cursor-\(id)",
                    type: .toolCall(tool),
                    timestamp: timestamp
                )
            }

            if let thinking = dictionary(bubble?["thinking"]),
                let text = normalizedText(thinking["text"])
            {
                return ChatHistoryItem(
                    id: "cursor-\(id)",
                    type: .thinking(text),
                    timestamp: timestamp
                )
            }

            guard let text = normalizedText(bubble?["text"]) ?? groupingPreview else {
                return nil
            }
            return ChatHistoryItem(
                id: "cursor-\(id)",
                type: .assistant(text),
                timestamp: timestamp
            )
        }
    }

    private nonisolated static func parsedToolCall(
        from bubble: [String: Any]?,
        phase: SessionPhase,
        composerStatus: String?
    ) -> ToolCallItem? {
        guard let toolData = dictionary(bubble?["toolFormerData"]),
            let name = normalizedText(toolData["name"])
        else {
            return nil
        }

        let rawInput =
            jsonObjectValue(toolData["params"])
            ?? jsonObjectValue(toolData["rawArgs"])
            ?? [:]
        let input = normalizedToolInput(rawInput)
        let result = SessionTextSanitizer.boundedMultilineDisplayText(
            toolData["result"] as? String,
            maxCharacters: 2_000,
            truncationNotice: "…"
        )

        return ToolCallItem(
            name: name,
            input: input,
            status: toolStatus(
                normalizedText(toolData["status"]),
                phase: phase,
                composerStatus: composerStatus
            ),
            result: result,
            structuredResult: nil,
            subagentTools: []
        )
    }

    private nonisolated static func jsonObjectValue(_ value: Any?) -> [String: Any]? {
        if let value = value as? [String: Any] { return value }
        guard let value = value as? String else { return nil }
        return jsonObject(value)
    }

    private nonisolated static func normalizedToolInput(
        _ input: [String: Any]
    ) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in input {
            let normalizedKey: String
            switch key {
            case "targetFile", "effectiveUri", "targetDirectory":
                normalizedKey = "path"
            case "globPattern":
                normalizedKey = "pattern"
            default:
                normalizedKey = key
            }

            let text: String?
            if let value = value as? String {
                text = normalizedText(value)
            } else if let value = value as? NSNumber {
                text = value.stringValue
            } else if JSONSerialization.isValidJSONObject(value),
                let data = try? JSONSerialization.data(withJSONObject: value),
                let json = String(data: data, encoding: .utf8)
            {
                text = normalizedText(json)
            } else {
                text = nil
            }

            if let text {
                result[normalizedKey] = String(text.prefix(600))
            }
        }
        return result
    }

    private nonisolated static func toolStatus(
        _ rawStatus: String?,
        phase: SessionPhase,
        composerStatus: String?
    ) -> ToolStatus {
        switch rawStatus?.lowercased() {
        case "completed", "complete", "success", "succeeded":
            return .success
        case "error", "failed", "failure":
            return .error
        case "cancelled", "canceled", "aborted", "interrupted":
            return .interrupted
        case "waiting", "pending_approval", "waiting_for_approval":
            return .waitingForApproval
        case "loading", "running", "pending", "in_progress":
            if phase.isActive || phase.needsAttention {
                return .running
            }
            return composerStatus == "completed" ? .success : .interrupted
        default:
            if phase.isActive || phase.needsAttention { return .running }
            return composerStatus == "completed" ? .success : .interrupted
        }
    }

    private nonisolated static func phase(
        header: [String: Any],
        composer: [String: Any]
    ) -> SessionPhase {
        if boolValue(header["hasBlockingPendingActions"]) {
            return .waitingForInput
        }

        if let generating = composer["generatingBubbleIds"] as? [Any], !generating.isEmpty {
            return .processing
        }

        // Cursor 2.x assigns a transient generation UUID for the lifetime of an
        // active turn and clears it when the turn finishes. During that turn the
        // persisted `status` may still describe the previous turn as completed,
        // so the UUID must take precedence over the stale terminal status.
        if normalizedText(composer["chatGenerationUUID"]) != nil {
            return .processing
        }

        if boolValue(composer["isContinuationInProgress"])
            || boolValue(composer["isApplyingWorktree"])
            || boolValue(composer["isCreatingWorktree"])
        {
            return .processing
        }

        switch normalizedText(composer["status"])?.lowercased() {
        case nil, "none", "completed", "aborted":
            return .idle
        default:
            return .processing
        }
    }

    private nonisolated static func workspacePath(in object: [String: Any]) -> String? {
        let candidates: [[String]] = [
            ["workspaceIdentifier", "uri", "fsPath"],
            ["workspaceIdentifier", "uri", "path"],
            ["agentLocation", "environment", "uri", "fsPath"],
            ["agentLocation", "environment", "uri", "path"],
            ["draftTarget", "environment", "uri", "fsPath"],
            ["draftTarget", "environment", "uri", "path"],
        ]

        for path in candidates {
            var current: Any = object
            for component in path {
                guard let next = dictionary(current)?[component] else {
                    current = NSNull()
                    break
                }
                current = next
            }
            if let value = normalizedText(current),
                let normalized = normalizedWorkspacePath(value)
            {
                return normalized
            }
        }
        return nil
    }

    private nonisolated static func normalizedWorkspacePath(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        if value.lowercased().hasPrefix("file://"), let url = URL(string: value), url.isFileURL {
            return url.standardizedFileURL.path
        }
        return URL(fileURLWithPath: value.removingPercentEncoding ?? value).standardizedFileURL.path
    }

    private nonisolated static func jsonObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private nonisolated static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private nonisolated static func normalizedText(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        return SessionTextSanitizer.sanitizedDisplayText(value)
    }

    private nonisolated static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return false
    }

    private nonisolated static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private nonisolated static func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return nil
    }

    private nonisolated static func date(milliseconds: Int64) -> Date {
        guard milliseconds > 0 else { return Date() }
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }

    private nonisolated static func iso8601Date(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}

actor CursorConversationMonitor {
    static let shared = CursorConversationMonitor()

    private static let logger = Logger(
        subsystem: MacIslandProductPolicy.loggingSubsystem,
        category: "CursorConversationMonitor"
    )
    private static let cursorBundleIdentifier = "com.todesktop.230313mzl4w4u92"
    private static let refreshInterval: Duration = .milliseconds(500)
    private static let recentConversationWindow: TimeInterval = 30 * 60

    private let userDataRoot: URL
    private var pollingTask: Task<Void, Never>?
    private var lastDatabaseFingerprint: String?

    init(userDataRoot: URL? = nil) {
        self.userDataRoot =
            userDataRoot
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User", isDirectory: true)
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled else { break }
                await self.refresh(force: false)
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        lastDatabaseFingerprint = nil
    }

    func readRecentSnapshots(now: Date = Date()) -> [CursorConversationSnapshot] {
        let databaseURL = userDataRoot.appendingPathComponent("globalStorage/state.vscdb")
        guard let database = CursorReadOnlySQLiteDatabase.open(path: databaseURL.path) else {
            return []
        }
        defer { database.close() }

        let cutoff = Int64(now.addingTimeInterval(-Self.recentConversationWindow).timeIntervalSince1970 * 1_000)
        let workspaceStorageRoot = userDataRoot.appendingPathComponent("workspaceStorage", isDirectory: true)

        return database.recentConversations(updatedSinceMilliseconds: cutoff).compactMap { row in
            CursorConversationParser.parse(
                composerId: row.composerId,
                workspaceId: row.workspaceId,
                createdAtMilliseconds: row.createdAtMilliseconds,
                updatedAtMilliseconds: row.updatedAtMilliseconds,
                headerJSON: row.headerJSON,
                composerJSON: row.composerJSON,
                fallbackWorkspacePath: Self.workspacePath(
                    workspaceId: row.workspaceId,
                    workspaceStorageRoot: workspaceStorageRoot
                ),
                bubbleJSONByID: database.bubbleJSONByID(composerId: row.composerId)
            )
        }
    }

    private func refresh(force: Bool) async {
        let databaseURL = userDataRoot.appendingPathComponent("globalStorage/state.vscdb")
        let fingerprint = Self.databaseFingerprint(databaseURL: databaseURL)
        guard force || fingerprint != lastDatabaseFingerprint else { return }
        lastDatabaseFingerprint = fingerprint

        let snapshots = readRecentSnapshots()
        guard !snapshots.isEmpty else { return }
        await SessionStore.shared.syncCursorConversationSnapshots(snapshots)
        Self.logger.debug("Refreshed \(snapshots.count, privacy: .public) local Cursor session snapshots")
    }

    private nonisolated static func workspacePath(
        workspaceId: String?,
        workspaceStorageRoot: URL
    ) -> String? {
        guard let workspaceId, !workspaceId.isEmpty else { return nil }
        let url =
            workspaceStorageRoot
            .appendingPathComponent(workspaceId, isDirectory: true)
            .appendingPathComponent("workspace.json")
        guard let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let folder = json["folder"] as? String,
            let folderURL = URL(string: folder),
            folderURL.isFileURL
        else {
            return nil
        }
        return folderURL.standardizedFileURL.path
    }

    private nonisolated static func databaseFingerprint(databaseURL: URL) -> String {
        let urls = [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
        ]
        return urls.map { url in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes?[.size] as? NSNumber
            let date = attributes?[.modificationDate] as? Date
            return "\(url.lastPathComponent):\(size?.int64Value ?? -1):\(date?.timeIntervalSince1970 ?? -1)"
        }.joined(separator: "|")
    }
}

struct CursorLocalAccountAuthorization: Sendable {
    let accessToken: String
    let planName: String?
}

/// Reads only the two account fields needed by the explicitly opted-in Cursor
/// quota integration. The access token remains in memory for a single request
/// and is never logged, cached, or included in diagnostics.
enum CursorLocalAccountAuthorizationReader {
    nonisolated static let defaultDatabaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(
            "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        )

    nonisolated static func read(
        databaseURL: URL = defaultDatabaseURL
    ) -> CursorLocalAccountAuthorization? {
        guard let database = CursorReadOnlySQLiteDatabase.open(path: databaseURL.path) else {
            return nil
        }
        defer { database.close() }

        let accessToken =
            database.itemValue(forKey: "cursorAuth/accessToken")
            ?? database.itemValue(forKey: "cursor.accessToken")
        guard let accessToken = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
            !accessToken.isEmpty
        else {
            return nil
        }
        return CursorLocalAccountAuthorization(
            accessToken: accessToken,
            planName: database.itemValue(forKey: "cursorAuth/stripeMembershipType")
        )
    }
}

nonisolated private struct CursorSQLiteConversationRow {
    let composerId: String
    let workspaceId: String?
    let createdAtMilliseconds: Int64
    let updatedAtMilliseconds: Int64
    let headerJSON: String
    let composerJSON: String?
}

nonisolated private final class CursorReadOnlySQLiteDatabase: @unchecked Sendable {
    fileprivate typealias OpenV2 =
        @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<OpaquePointer?>?, Int32, UnsafePointer<CChar>?) ->
        Int32
    fileprivate typealias Close = @convention(c) (OpaquePointer?) -> Int32
    fileprivate typealias PrepareV2 =
        @convention(c) (
            OpaquePointer?, UnsafePointer<CChar>?, Int32, UnsafeMutablePointer<OpaquePointer?>?,
            UnsafeMutablePointer<UnsafePointer<CChar>?>?
        ) -> Int32
    fileprivate typealias Step = @convention(c) (OpaquePointer?) -> Int32
    fileprivate typealias Finalize = @convention(c) (OpaquePointer?) -> Int32
    fileprivate typealias ColumnText = @convention(c) (OpaquePointer?, Int32) -> UnsafePointer<UInt8>?
    fileprivate typealias ColumnInt64 = @convention(c) (OpaquePointer?, Int32) -> Int64
    fileprivate typealias BindInt64 = @convention(c) (OpaquePointer?, Int32, Int64) -> Int32
    fileprivate typealias BindText =
        @convention(c) (
            OpaquePointer?, Int32, UnsafePointer<CChar>?, Int32, (@convention(c) (UnsafeMutableRawPointer?) -> Void)?
        ) -> Int32

    private static let openReadOnly: Int32 = 0x0000_0001
    private static let sqliteRow: Int32 = 100
    private let handle: OpaquePointer?
    private let symbols: CursorSQLiteSymbols

    private init(handle: OpaquePointer?, symbols: CursorSQLiteSymbols) {
        self.handle = handle
        self.symbols = symbols
    }

    static func open(path: String) -> CursorReadOnlySQLiteDatabase? {
        guard let symbols = CursorSQLiteSymbols.load() else { return nil }
        var handle: OpaquePointer?
        let result = path.withCString { symbols.openV2($0, &handle, openReadOnly, nil) }
        guard result == 0 else {
            if handle != nil { _ = symbols.close(handle) }
            return nil
        }
        return CursorReadOnlySQLiteDatabase(handle: handle, symbols: symbols)
    }

    func close() {
        _ = symbols.close(handle)
    }

    func recentConversations(updatedSinceMilliseconds: Int64) -> [CursorSQLiteConversationRow] {
        let query = """
            SELECT h.composerId,
                   h.workspaceId,
                   h.createdAt,
                   COALESCE(h.lastUpdatedAt, h.recency, h.createdAt),
                   h.value,
                   d.value
            FROM composerHeaders AS h
            LEFT JOIN cursorDiskKV AS d ON d.key = ('composerData:' || h.composerId)
            WHERE h.isArchived = 0
              AND h.isSubagent = 0
              AND h.composerId <> 'empty-state-draft'
              AND COALESCE(h.lastUpdatedAt, h.recency, h.createdAt) >= ?
            ORDER BY COALESCE(h.lastUpdatedAt, h.recency, h.createdAt) DESC
            LIMIT 32
            """

        var statement: OpaquePointer?
        guard query.withCString({ symbols.prepareV2(handle, $0, -1, &statement, nil) }) == 0 else {
            return []
        }
        defer { _ = symbols.finalize(statement) }
        guard symbols.bindInt64(statement, 1, updatedSinceMilliseconds) == 0 else { return [] }

        var rows: [CursorSQLiteConversationRow] = []
        while symbols.step(statement) == Self.sqliteRow {
            guard let composerId = textColumn(statement, 0),
                let headerJSON = textColumn(statement, 4)
            else {
                continue
            }
            rows.append(
                CursorSQLiteConversationRow(
                    composerId: composerId,
                    workspaceId: textColumn(statement, 1),
                    createdAtMilliseconds: symbols.columnInt64(statement, 2),
                    updatedAtMilliseconds: symbols.columnInt64(statement, 3),
                    headerJSON: headerJSON,
                    composerJSON: textColumn(statement, 5)
                ))
        }
        return rows
    }

    func bubbleJSONByID(composerId: String) -> [String: String] {
        let prefix = "bubbleId:\(composerId):"
        let query = "SELECT key, value FROM cursorDiskKV WHERE key >= ? AND key < ?"
        var statement: OpaquePointer?
        guard query.withCString({ symbols.prepareV2(handle, $0, -1, &statement, nil) }) == 0 else {
            return [:]
        }
        defer { _ = symbols.finalize(statement) }

        let upperBound = prefix + "\u{10ffff}"
        return prefix.withCString { lowerPointer in
            upperBound.withCString { upperPointer in
                guard symbols.bindText(statement, 1, lowerPointer, -1, nil) == 0,
                    symbols.bindText(statement, 2, upperPointer, -1, nil) == 0
                else {
                    return [:]
                }

                var result: [String: String] = [:]
                while symbols.step(statement) == Self.sqliteRow {
                    guard let key = textColumn(statement, 0),
                        let value = textColumn(statement, 1),
                        key.hasPrefix(prefix)
                    else {
                        continue
                    }
                    result[String(key.dropFirst(prefix.count))] = value
                }
                return result
            }
        }
    }

    func itemValue(forKey key: String) -> String? {
        let query = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"
        var statement: OpaquePointer?
        guard query.withCString({ symbols.prepareV2(handle, $0, -1, &statement, nil) }) == 0 else {
            return nil
        }
        defer { _ = symbols.finalize(statement) }

        return key.withCString { keyPointer in
            guard symbols.bindText(statement, 1, keyPointer, -1, nil) == 0,
                symbols.step(statement) == Self.sqliteRow
            else {
                return nil
            }
            return textColumn(statement, 0)
        }
    }

    private func textColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let bytes = symbols.columnText(statement, index) else { return nil }
        return String(cString: UnsafeRawPointer(bytes).assumingMemoryBound(to: CChar.self))
    }
}

nonisolated private struct CursorSQLiteSymbols: @unchecked Sendable {
    let library: UnsafeMutableRawPointer
    let openV2: CursorReadOnlySQLiteDatabase.OpenV2
    let close: CursorReadOnlySQLiteDatabase.Close
    let prepareV2: CursorReadOnlySQLiteDatabase.PrepareV2
    let step: CursorReadOnlySQLiteDatabase.Step
    let finalize: CursorReadOnlySQLiteDatabase.Finalize
    let columnText: CursorReadOnlySQLiteDatabase.ColumnText
    let columnInt64: CursorReadOnlySQLiteDatabase.ColumnInt64
    let bindInt64: CursorReadOnlySQLiteDatabase.BindInt64
    let bindText: CursorReadOnlySQLiteDatabase.BindText

    static func load() -> CursorSQLiteSymbols? {
        cached
    }

    private static let cached: CursorSQLiteSymbols? = {
        for libraryName in ["/usr/lib/libsqlite3.dylib", "libsqlite3.dylib"] {
            guard let library = dlopen(libraryName, RTLD_NOW | RTLD_LOCAL),
                let openV2: CursorReadOnlySQLiteDatabase.OpenV2 = symbol("sqlite3_open_v2", library),
                let close: CursorReadOnlySQLiteDatabase.Close = symbol("sqlite3_close", library),
                let prepareV2: CursorReadOnlySQLiteDatabase.PrepareV2 = symbol("sqlite3_prepare_v2", library),
                let step: CursorReadOnlySQLiteDatabase.Step = symbol("sqlite3_step", library),
                let finalize: CursorReadOnlySQLiteDatabase.Finalize = symbol("sqlite3_finalize", library),
                let columnText: CursorReadOnlySQLiteDatabase.ColumnText = symbol("sqlite3_column_text", library),
                let columnInt64: CursorReadOnlySQLiteDatabase.ColumnInt64 = symbol("sqlite3_column_int64", library),
                let bindInt64: CursorReadOnlySQLiteDatabase.BindInt64 = symbol("sqlite3_bind_int64", library),
                let bindText: CursorReadOnlySQLiteDatabase.BindText = symbol("sqlite3_bind_text", library)
            else {
                continue
            }
            return CursorSQLiteSymbols(
                library: library,
                openV2: openV2,
                close: close,
                prepareV2: prepareV2,
                step: step,
                finalize: finalize,
                columnText: columnText,
                columnInt64: columnInt64,
                bindInt64: bindInt64,
                bindText: bindText
            )
        }
        return nil
    }()

    private static func symbol<T>(_ name: String, _ library: UnsafeMutableRawPointer) -> T? {
        guard let pointer = dlsym(library, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
