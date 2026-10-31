import Darwin
import Foundation

/// Metadata-only snapshot recovered after Mac Island relaunches.
///
/// Recovery deliberately excludes prompts, assistant output, tool arguments,
/// tool results, credentials, and message/part tables. Live hooks remain the
/// authoritative source once a client emits its next event.
struct ObservedRecoveredSession: Equatable, Sendable {
    let nativeSessionID: String
    let client: MacIslandClientKind
    let origin: MacIslandSessionOrigin
    let cwd: String
    let nativeTitle: String?
    let serviceProvider: String?
    let modelName: String?
    let lastActivity: Date

    nonisolated var clientInfo: SessionClientInfo {
        switch client {
        case .claudeCode:
            return SessionClientInfo(
                kind: .claudeCode,
                profileID: origin == .desktop ? "claude-desktop-code" : "claude-code",
                name: origin == .desktop ? "Claude Desktop · Code" : "Claude Code",
                bundleIdentifier: origin == .desktop ? "com.anthropic.claudefordesktop" : nil,
                origin: origin.rawValue,
                originator: origin == .desktop ? "Claude Desktop · Code" : "Claude Code",
                threadSource: "claude-recovery"
            )
        case .openCode:
            return SessionClientInfo(
                kind: .custom,
                profileID: "opencode",
                name: origin == .desktop ? "OpenCode Desktop" : "OpenCode",
                bundleIdentifier: origin == .desktop ? "ai.opencode.desktop" : nil,
                origin: origin.rawValue,
                originator: "OpenCode",
                threadSource: "opencode-recovery"
            )
        case .hermes:
            return SessionClientInfo(
                kind: .custom,
                profileID: "hermes",
                name: origin == .desktop ? "Hermes Desktop" : "Hermes",
                bundleIdentifier: origin == .desktop ? "com.nousresearch.hermes.setup" : nil,
                origin: origin.rawValue,
                originator: "Hermes",
                threadSource: "hermes-recovery"
            )
        case .dsh:
            return SessionClientInfo(
                kind: .custom,
                profileID: "dsh",
                name: origin == .web ? "DeepSeek Harness Web" : "DeepSeek Harness",
                launchURL: origin == .web ? "http://127.0.0.1:3080" : nil,
                origin: origin.rawValue,
                originator: "DeepSeek Harness",
                threadSource: "dsh-recovery"
            )
        }
    }

    nonisolated var sessionID: String {
        MacIslandProductPolicy.observedSessionKey(
            nativeSessionID: nativeSessionID,
            clientInfo: clientInfo
        )
    }
}

enum ObservedSessionRecovery {
    static let recentWindow: TimeInterval = 30 * 60

    static let defaultOpenCodeDatabaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/opencode/opencode.db")
    static let defaultHermesDatabaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".hermes/state.db")

    static func loadOpenCode(
        databaseURL: URL = defaultOpenCodeDatabaseURL,
        now: Date = Date()
    ) -> [ObservedRecoveredSession] {
        guard let database = ObservedReadOnlySQLiteDatabase.open(path: databaseURL.path) else {
            return []
        }
        defer { database.close() }

        let requiredColumns: Set<String> = [
            "id", "parent_id", "directory", "title", "model", "time_updated",
        ]
        guard requiredColumns.isSubset(of: database.columns(in: "session")) else {
            return []
        }

        let cutoffMilliseconds = Int64(
            now.addingTimeInterval(-recentWindow).timeIntervalSince1970 * 1_000
        )
        let query = """
            SELECT id, directory, title, model, time_updated
            FROM session
            WHERE parent_id IS NULL
              AND time_updated >= \(cutoffMilliseconds)
            ORDER BY time_updated DESC
            LIMIT 20
            """

        return database.rows(query: query, columnCount: 5).compactMap { row in
            guard let nativeSessionID = normalizedOptionalText(row.text(at: 0)),
                let cwd = normalizedOptionalText(row.text(at: 1))
            else {
                return nil
            }
            let model = openCodeModelMetadata(row.text(at: 3))
            return ObservedRecoveredSession(
                nativeSessionID: nativeSessionID,
                client: .openCode,
                // This schema does not identify CLI versus Desktop ownership.
                origin: .unknown,
                cwd: cwd,
                nativeTitle: normalizedOptionalText(row.text(at: 2)),
                serviceProvider: model.provider,
                modelName: model.name,
                lastActivity: Date(timeIntervalSince1970: Double(row.int64(at: 4)) / 1_000)
            )
        }
    }

    static func loadHermes(
        databaseURL: URL = defaultHermesDatabaseURL,
        now: Date = Date()
    ) -> [ObservedRecoveredSession] {
        guard let database = ObservedReadOnlySQLiteDatabase.open(path: databaseURL.path) else {
            return []
        }
        defer { database.close() }

        let requiredColumns: Set<String> = [
            "id", "source", "model", "billing_provider", "title", "cwd",
            "started_at", "last_activity_at", "parent_session_id",
        ]
        guard requiredColumns.isSubset(of: database.columns(in: "sessions")) else {
            return []
        }

        let cutoffSeconds = now.addingTimeInterval(-recentWindow).timeIntervalSince1970
        let query = """
            SELECT id, source, model, billing_provider, title, cwd,
                   COALESCE(last_activity_at, started_at)
            FROM sessions
            WHERE parent_session_id IS NULL
              AND source IN ('cli', 'desktop')
              AND COALESCE(last_activity_at, started_at) >= \(cutoffSeconds)
            ORDER BY COALESCE(last_activity_at, started_at) DESC
            LIMIT 20
            """

        return database.rows(query: query, columnCount: 7).compactMap { row in
            guard let nativeSessionID = normalizedOptionalText(row.text(at: 0)),
                let rawOrigin = row.text(at: 1)?.lowercased(),
                let origin = MacIslandSessionOrigin(rawValue: rawOrigin),
                let cwd = normalizedOptionalText(row.text(at: 5))
            else {
                return nil
            }
            return ObservedRecoveredSession(
                nativeSessionID: nativeSessionID,
                client: .hermes,
                origin: origin,
                cwd: cwd,
                nativeTitle: normalizedOptionalText(row.text(at: 4)),
                serviceProvider: normalizedOptionalText(row.text(at: 3)),
                modelName: normalizedOptionalText(row.text(at: 2)),
                lastActivity: Date(timeIntervalSince1970: row.double(at: 6))
            )
        }
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !normalized.isEmpty
        else {
            return nil
        }
        return normalized
    }

    private static func openCodeModelMetadata(
        _ rawValue: String?
    ) -> (provider: String?, name: String?) {
        guard let rawValue = normalizedOptionalText(rawValue) else {
            return (nil, nil)
        }
        guard let data = rawValue.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (nil, rawValue)
        }
        return (
            normalizedOptionalText(object["providerID"] as? String),
            normalizedOptionalText(object["id"] as? String)
        )
    }
}

private struct ObservedSQLiteRow {
    fileprivate let values: [String?]

    func text(at index: Int32) -> String? {
        guard index >= 0, Int(index) < values.count else { return nil }
        return values[Int(index)]
    }

    func int64(at index: Int32) -> Int64 {
        guard let value = text(at: index) else { return 0 }
        return Int64(value) ?? Int64(Double(value) ?? 0)
    }

    func double(at index: Int32) -> Double {
        guard let value = text(at: index) else { return 0 }
        return Double(value) ?? 0
    }
}

private final class ObservedReadOnlySQLiteDatabase {
    fileprivate typealias OpenV2 =
        @convention(c) (
            UnsafePointer<CChar>?, UnsafeMutablePointer<OpaquePointer?>?, Int32, UnsafePointer<CChar>?
        ) -> Int32
    fileprivate typealias Close = @convention(c) (OpaquePointer?) -> Int32
    fileprivate typealias PrepareV2 =
        @convention(c) (
            OpaquePointer?, UnsafePointer<CChar>?, Int32,
            UnsafeMutablePointer<OpaquePointer?>?, UnsafeMutablePointer<UnsafePointer<CChar>?>?
        ) -> Int32
    fileprivate typealias Step = @convention(c) (OpaquePointer?) -> Int32
    fileprivate typealias Finalize = @convention(c) (OpaquePointer?) -> Int32
    fileprivate typealias ColumnText = @convention(c) (OpaquePointer?, Int32) -> UnsafePointer<UInt8>?
    fileprivate typealias ColumnInt64 = @convention(c) (OpaquePointer?, Int32) -> Int64
    fileprivate typealias ColumnDouble = @convention(c) (OpaquePointer?, Int32) -> Double

    private static let openReadOnly: Int32 = 0x0000_0001
    private static let sqliteRow: Int32 = 100
    private let handle: OpaquePointer?
    private let symbols: ObservedSQLiteSymbols

    private init(handle: OpaquePointer?, symbols: ObservedSQLiteSymbols) {
        self.handle = handle
        self.symbols = symbols
    }

    // Both recovery loaders close the handle with defer before releasing this wrapper.
    // No actor work remains at teardown; avoid the older macOS isolated-deinit back-deploy path.
    nonisolated deinit {}

    static func open(path: String) -> ObservedReadOnlySQLiteDatabase? {
        guard let symbols = ObservedSQLiteSymbols.load() else { return nil }
        var handle: OpaquePointer?
        let result = path.withCString { symbols.openV2($0, &handle, openReadOnly, nil) }
        guard result == 0 else {
            if handle != nil { _ = symbols.close(handle) }
            return nil
        }
        return ObservedReadOnlySQLiteDatabase(handle: handle, symbols: symbols)
    }

    func close() {
        _ = symbols.close(handle)
    }

    func columns(in table: String) -> Set<String> {
        guard table == "session" || table == "sessions" else { return [] }
        return Set(
            rows(query: "PRAGMA table_info(\(table))", columnCount: 6).compactMap {
                $0.text(at: 1)
            })
    }

    func rows(query: String, columnCount: Int32) -> [ObservedSQLiteRow] {
        var statement: OpaquePointer?
        guard query.withCString({ symbols.prepareV2(handle, $0, -1, &statement, nil) }) == 0 else {
            return []
        }
        defer { _ = symbols.finalize(statement) }

        var result: [ObservedSQLiteRow] = []
        while symbols.step(statement) == Self.sqliteRow {
            let values = (0..<columnCount).map { index -> String? in
                guard let bytes = symbols.columnText(statement, index) else { return nil }
                return String(cString: UnsafeRawPointer(bytes).assumingMemoryBound(to: CChar.self))
            }
            result.append(ObservedSQLiteRow(values: values))
        }
        return result
    }
}

private struct ObservedSQLiteSymbols: @unchecked Sendable {
    let library: UnsafeMutableRawPointer
    let openV2: ObservedReadOnlySQLiteDatabase.OpenV2
    let close: ObservedReadOnlySQLiteDatabase.Close
    let prepareV2: ObservedReadOnlySQLiteDatabase.PrepareV2
    let step: ObservedReadOnlySQLiteDatabase.Step
    let finalize: ObservedReadOnlySQLiteDatabase.Finalize
    let columnText: ObservedReadOnlySQLiteDatabase.ColumnText
    let columnInt64: ObservedReadOnlySQLiteDatabase.ColumnInt64
    let columnDouble: ObservedReadOnlySQLiteDatabase.ColumnDouble

    static func load() -> ObservedSQLiteSymbols? {
        cached
    }

    private static let cached: ObservedSQLiteSymbols? = {
        for libraryName in ["/usr/lib/libsqlite3.dylib", "libsqlite3.dylib"] {
            guard let library = dlopen(libraryName, RTLD_NOW | RTLD_LOCAL),
                let openV2: ObservedReadOnlySQLiteDatabase.OpenV2 = symbol("sqlite3_open_v2", library),
                let close: ObservedReadOnlySQLiteDatabase.Close = symbol("sqlite3_close", library),
                let prepareV2: ObservedReadOnlySQLiteDatabase.PrepareV2 = symbol("sqlite3_prepare_v2", library),
                let step: ObservedReadOnlySQLiteDatabase.Step = symbol("sqlite3_step", library),
                let finalize: ObservedReadOnlySQLiteDatabase.Finalize = symbol("sqlite3_finalize", library),
                let columnText: ObservedReadOnlySQLiteDatabase.ColumnText = symbol("sqlite3_column_text", library),
                let columnInt64: ObservedReadOnlySQLiteDatabase.ColumnInt64 = symbol("sqlite3_column_int64", library),
                let columnDouble: ObservedReadOnlySQLiteDatabase.ColumnDouble = symbol("sqlite3_column_double", library)
            else {
                continue
            }
            return ObservedSQLiteSymbols(
                library: library,
                openV2: openV2,
                close: close,
                prepareV2: prepareV2,
                step: step,
                finalize: finalize,
                columnText: columnText,
                columnInt64: columnInt64,
                columnDouble: columnDouble
            )
        }
        return nil
    }()

    private static func symbol<T>(
        _ name: String,
        _ library: UnsafeMutableRawPointer
    ) -> T? {
        guard let pointer = dlsym(library, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
