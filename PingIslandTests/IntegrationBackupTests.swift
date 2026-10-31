import XCTest

@testable import Ping_Island

final class IntegrationBackupTests: XCTestCase {
    func testBackupAndRollbackRestoreFilesDirectoriesAndAbsence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-island-backup-test-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        let settings = home.appendingPathComponent(".claude/settings.json")
        let pluginDirectory = home.appendingPathComponent(".hermes/plugins/mac_island", isDirectory: true)
        let absentPlugin = home.appendingPathComponent(".config/opencode/plugins/mac-island.js")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"existing":true}"#.utf8).write(to: settings, options: .atomic)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try Data("original plugin".utf8).write(
            to: pluginDirectory.appendingPathComponent("__init__.py"),
            options: .atomic
        )

        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let backup = try XCTUnwrap(
            HookInstaller.createIntegrationBackup(
                profileID: "test-hooks",
                targets: [settings, pluginDirectory, absentPlugin],
                backupRoot: backupRoot,
                now: createdAt
            )
        )

        try Data(#"{"changed":true}"#.utf8).write(to: settings, options: .atomic)
        try FileManager.default.removeItem(at: pluginDirectory)
        try FileManager.default.createDirectory(
            at: absentPlugin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("new plugin".utf8).write(to: absentPlugin, options: .atomic)

        XCTAssertTrue(HookInstaller.restoreIntegrationBackup(at: backup.directoryURL, allowedRoot: home))
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), #"{"existing":true}"#)
        XCTAssertEqual(
            try String(contentsOf: pluginDirectory.appendingPathComponent("__init__.py"), encoding: .utf8),
            "original plugin"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: absentPlugin.path))
        XCTAssertEqual(
            HookInstaller.latestIntegrationBackup(profileID: "test-hooks", backupRoot: backupRoot)?.createdAt,
            createdAt
        )
    }

    func testRestoreRejectsTargetsOutsideAllowedRootBeforeChangingAnything() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-island-backup-boundary-\(UUID().uuidString)", isDirectory: true)
        let allowed = root.appendingPathComponent("allowed", isDirectory: true)
        let outside = root.appendingPathComponent("outside.txt")
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: outside, options: .atomic)
        let backup = try XCTUnwrap(
            HookInstaller.createIntegrationBackup(
                profileID: "boundary-hooks",
                targets: [outside],
                backupRoot: backupRoot
            )
        )
        try Data("changed".utf8).write(to: outside, options: .atomic)

        XCTAssertFalse(HookInstaller.restoreIntegrationBackup(at: backup.directoryURL, allowedRoot: allowed))
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "changed")
    }
}
