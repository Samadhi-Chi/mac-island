import XCTest

@testable import Ping_Island

final class VibeHookMigrationTests: XCTestCase {
    func testMigrationRemovesOnlyVibeCommandsAndCreatesBackup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = root.appendingPathComponent("hooks.json")
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let original: [String: Any] = [
            "version": 1,
            "hooks": [
                "stop": [
                    ["command": "/Users/demo/.vibe-island/bin/vibe-island-bridge --source cursor"],
                    ["command": "/usr/local/bin/my-observer"],
                ],
                "sessionStart": [
                    [
                        "matcher": "*",
                        "hooks": [
                            [
                                "type": "command",
                                "command": "/Users/demo/.vibe-island/bin/vibe-island-bridge --source codex",
                            ]
                        ],
                    ]
                ],
            ],
            "unrelated": ["enabled": true],
        ]
        let originalData = try JSONSerialization.data(withJSONObject: original, options: [.sortedKeys])
        try originalData.write(to: configURL)

        XCTAssertEqual(try VibeHookMigration.preview(fileURL: configURL).managedEntryCount, 2)
        let result = try VibeHookMigration.migrate(
            fileURL: configURL,
            backupRootURL: backupRoot,
            date: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(result.removedEntryCount, 2)
        XCTAssertNotNil(result.backupURL)
        XCTAssertEqual(try VibeHookMigration.preview(fileURL: configURL).managedEntryCount, 0)

        let migratedData = try Data(contentsOf: configURL)
        let migrated = try XCTUnwrap(
            JSONSerialization.jsonObject(with: migratedData) as? [String: Any]
        )
        let hooks = try XCTUnwrap(migrated["hooks"] as? [String: Any])
        let stop = try XCTUnwrap(hooks["stop"] as? [[String: Any]])
        XCTAssertEqual(stop.count, 1)
        XCTAssertEqual(stop.first?["command"] as? String, "/usr/local/bin/my-observer")
        XCTAssertEqual((migrated["unrelated"] as? [String: Any])?["enabled"] as? Bool, true)

        let second = try VibeHookMigration.migrate(fileURL: configURL, backupRootURL: backupRoot)
        XCTAssertEqual(second.removedEntryCount, 0)
        XCTAssertNil(second.backupURL)
    }

    func testSameNamedHookFilesFromDifferentClientsGetDistinctBackups() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codexURL = root.appendingPathComponent("codex/hooks.json")
        let cursorURL = root.appendingPathComponent("cursor/hooks.json")
        for url in [codexURL, cursorURL] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let payload: [String: Any] = [
                "hooks": [["command": "/Users/demo/.vibe-island/bin/vibe-island-bridge"]]
            ]
            try JSONSerialization.data(withJSONObject: payload).write(to: url)
        }

        let date = Date(timeIntervalSince1970: 0)
        let codex = try VibeHookMigration.migrate(
            fileURL: codexURL,
            backupRootURL: backupRoot,
            date: date
        )
        let cursor = try VibeHookMigration.migrate(
            fileURL: cursorURL,
            backupRootURL: backupRoot,
            date: date
        )

        XCTAssertNotEqual(codex.backupURL, cursor.backupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(codex.backupURL).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(cursor.backupURL).path))
    }

    func testMalformedJSONFailsWithoutOverwritingSource() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = root.appendingPathComponent("hooks.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let malformed = Data("{not-json".utf8)
        try malformed.write(to: configURL)

        XCTAssertThrowsError(
            try VibeHookMigration.migrate(
                fileURL: configURL,
                backupRootURL: root.appendingPathComponent("backups")
            )
        )
        XCTAssertEqual(try Data(contentsOf: configURL), malformed)
    }
}
