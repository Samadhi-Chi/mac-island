import Foundation

enum VibeHookMigration {
    struct Preview: Equatable {
        let fileURL: URL
        let managedEntryCount: Int

        var needsMigration: Bool { managedEntryCount > 0 }
    }

    struct Result: Equatable {
        let fileURL: URL
        let backupURL: URL?
        let removedEntryCount: Int
    }

    enum MigrationError: Error {
        case invalidJSON(URL)
        case invalidRoot(URL)
    }

    private nonisolated static let vibeBridgeMarkers = [
        "/.vibe-island/bin/vibe-island-bridge",
        "\\.vibe-island\\bin\\vibe-island-bridge",
    ]

    static func preview(fileURL: URL) throws -> Preview {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Preview(fileURL: fileURL, managedEntryCount: 0)
        }

        let root = try readRoot(from: fileURL)
        return Preview(fileURL: fileURL, managedEntryCount: countManagedEntries(in: root))
    }

    /// Removes only Vibe Island-owned hook command objects. The caller decides
    /// when to install Mac Island hooks after reviewing the preview.
    static func migrate(
        fileURL: URL,
        backupRootURL: URL,
        date: Date = Date()
    ) throws -> Result {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Result(fileURL: fileURL, backupURL: nil, removedEntryCount: 0)
        }

        let originalData = try Data(contentsOf: fileURL)
        guard let root = try? JSONSerialization.jsonObject(with: originalData) else {
            throw MigrationError.invalidJSON(fileURL)
        }
        guard root is [String: Any] else {
            throw MigrationError.invalidRoot(fileURL)
        }

        let count = countManagedEntries(in: root)
        guard count > 0 else {
            return Result(fileURL: fileURL, backupURL: nil, removedEntryCount: 0)
        }

        let backupDirectory =
            backupRootURL
            .appendingPathComponent(timestamp(date), isDirectory: true)
        try FileManager.default.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let backupName = "\(fileURL.deletingLastPathComponent().lastPathComponent)-\(fileURL.lastPathComponent)"
        let backupURL = backupDirectory.appendingPathComponent(backupName)
        try originalData.write(to: backupURL, options: [.atomic])

        // The recursive cleaner intentionally removes empty nested hook containers.
        // When the root contains only Vibe-managed hooks, persist an empty object
        // instead of treating the valid cleanup result as an invalid root.
        let transformed = removingManagedEntries(from: root) as? [String: Any] ?? [:]
        let output = try JSONSerialization.data(
            withJSONObject: transformed,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try output.write(to: fileURL, options: [.atomic])

        return Result(fileURL: fileURL, backupURL: backupURL, removedEntryCount: count)
    }

    static func restore(backupURL: URL, destinationURL: URL) throws {
        let data = try Data(contentsOf: backupURL)
        _ = try JSONSerialization.jsonObject(with: data)
        try data.write(to: destinationURL, options: [.atomic])
    }

    nonisolated static func isVibeManagedCommand(_ command: String) -> Bool {
        let normalized = command.lowercased()
        return vibeBridgeMarkers.contains { normalized.contains($0) }
    }

    private static func readRoot(from url: URL) throws -> Any {
        let data = try Data(contentsOf: url)
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            throw MigrationError.invalidJSON(url)
        }
        guard root is [String: Any] else {
            throw MigrationError.invalidRoot(url)
        }
        return root
    }

    private nonisolated static func countManagedEntries(in value: Any) -> Int {
        if let dictionary = value as? [String: Any] {
            let ownCount = command(in: dictionary).map { isVibeManagedCommand($0) ? 1 : 0 } ?? 0
            return ownCount + dictionary.values.reduce(0) { $0 + countManagedEntries(in: $1) }
        }
        if let array = value as? [Any] {
            return array.reduce(0) { $0 + countManagedEntries(in: $1) }
        }
        return 0
    }

    private nonisolated static func removingManagedEntries(from value: Any) -> Any? {
        if let dictionary = value as? [String: Any] {
            if let command = command(in: dictionary), isVibeManagedCommand(command) {
                return nil
            }

            var transformed: [String: Any] = [:]
            for (key, child) in dictionary {
                if let next = removingManagedEntries(from: child) {
                    transformed[key] = next
                }
            }

            if dictionary["hooks"] is [Any],
                let hooks = transformed["hooks"] as? [Any],
                hooks.isEmpty
            {
                return nil
            }
            return transformed
        }

        if let array = value as? [Any] {
            return array.compactMap(removingManagedEntries(from:))
        }

        return value
    }

    private nonisolated static func command(in dictionary: [String: Any]) -> String? {
        ["command", "bash", "powershell"]
            .compactMap { dictionary[$0] as? String }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
