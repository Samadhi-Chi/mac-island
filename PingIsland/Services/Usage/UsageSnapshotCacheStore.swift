import Foundation

enum UsageSnapshotCacheStore {
    static let defaultDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(
            MacIslandProductPolicy.monitorOnly ? ".mac-island" : ".ping-island",
            isDirectory: true
        )
        .appendingPathComponent("cache", isDirectory: true)

    private static let claudeFileName = "claude-usage.json"
    private static let codexFileName = "codex-usage.json"
    private static let cursorFileName = "cursor-usage.json"

    static func loadClaude(from directoryURL: URL = defaultDirectoryURL) -> ClaudeUsageSnapshot? {
        guard let snapshot = load(ClaudeUsageSnapshot.self, from: directoryURL.appendingPathComponent(claudeFileName)),
            [snapshot.fiveHour, snapshot.sevenDay].compactMap({ $0 }).allSatisfy({
                ObservedNumber.percentage($0.usedPercentage) != nil && validDate($0.resetsAt)
            }), validDate(snapshot.cachedAt)
        else { return nil }
        return snapshot
    }

    static func saveClaude(_ snapshot: ClaudeUsageSnapshot, to directoryURL: URL = defaultDirectoryURL) {
        save(snapshot, to: directoryURL.appendingPathComponent(claudeFileName))
    }

    static func loadCodex(from directoryURL: URL = defaultDirectoryURL) -> CodexUsageSnapshot? {
        guard let snapshot = load(CodexUsageSnapshot.self, from: directoryURL.appendingPathComponent(codexFileName)),
            snapshot.windows.allSatisfy({
                ObservedNumber.percentage($0.usedPercentage) != nil
                    && $0.leftPercentage.isFinite && (0...100).contains($0.leftPercentage)
                    && $0.windowMinutes >= 0 && validDate($0.resetsAt)
            }), validDate(snapshot.capturedAt)
        else { return nil }
        return snapshot
    }

    static func saveCodex(_ snapshot: CodexUsageSnapshot, to directoryURL: URL = defaultDirectoryURL) {
        let projected =
            MacIslandProductPolicy.privacyShieldEnabled
            ? snapshot.quotaOnlyProjection
            : snapshot
        save(projected, to: directoryURL.appendingPathComponent(codexFileName))
    }

    static func loadCursor(from directoryURL: URL = defaultDirectoryURL) -> CursorUsageSnapshot? {
        guard let snapshot = load(CursorUsageSnapshot.self, from: directoryURL.appendingPathComponent(cursorFileName)),
            [snapshot.totalUsedPercentage, snapshot.apiUsedPercentage, snapshot.autoUsedPercentage]
                .compactMap({ $0 }).allSatisfy({ ObservedNumber.percentage($0) != nil }),
            validDate(snapshot.capturedAt), validDate(snapshot.billingCycleEnd)
        else { return nil }
        return snapshot
    }

    static func saveCursor(_ snapshot: CursorUsageSnapshot, to directoryURL: URL = defaultDirectoryURL) {
        save(snapshot, to: directoryURL.appendingPathComponent(cursorFileName))
    }

    private static func validDate(_ value: Date?) -> Bool {
        guard let value else { return true }
        return ObservedNumber.unixDate(value.timeIntervalSince1970) != nil
    }

    private static func load<T: Decodable>(_ type: T.Type, from fileURL: URL) -> T? {
        guard MacIslandRuntimeEnvironment.allowsLiveIO || fileURL.deletingLastPathComponent() != defaultDirectoryURL
        else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, to fileURL: URL) {
        guard MacIslandRuntimeEnvironment.allowsLiveIO || fileURL.deletingLastPathComponent() != defaultDirectoryURL
        else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: fileURL.deletingLastPathComponent().path
        )

        guard let data = try? JSONEncoder().encode(value) else {
            return
        }

        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
