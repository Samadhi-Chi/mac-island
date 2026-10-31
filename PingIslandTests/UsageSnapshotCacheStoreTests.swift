import XCTest

@testable import Ping_Island

final class UsageSnapshotCacheStoreTests: XCTestCase {
    func testSaveAndLoadClaudeSnapshot() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ping-island-usage-cache-\(UUID().uuidString)", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let snapshot = ClaudeUsageSnapshot(
            fiveHour: ClaudeUsageWindow(usedPercentage: 12, resetsAt: Date(timeIntervalSince1970: 1_760_000_000)),
            sevenDay: ClaudeUsageWindow(usedPercentage: 44, resetsAt: nil),
            cachedAt: Date(timeIntervalSince1970: 1_760_000_100)
        )

        UsageSnapshotCacheStore.saveClaude(snapshot, to: directoryURL)
        let loaded = UsageSnapshotCacheStore.loadClaude(from: directoryURL)

        XCTAssertEqual(loaded, snapshot)
    }

    func testSaveAndLoadCodexSnapshot() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ping-island-usage-cache-codex-\(UUID().uuidString)", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let snapshot = CodexUsageSnapshot(
            sourceFilePath: "/tmp/rollout.jsonl",
            capturedAt: Date(timeIntervalSince1970: 1_775_158_295),
            planType: "pro",
            limitID: "codex",
            tokenUsage: CodexTokenUsage(inputTokens: 100, outputTokens: 50, totalTokens: 150),
            windows: [
                CodexUsageWindow(
                    key: "primary",
                    label: "5h",
                    usedPercentage: 13,
                    leftPercentage: 87,
                    windowMinutes: 300,
                    resetsAt: Date(timeIntervalSince1970: 1_775_158_295)
                )
            ]
        )

        UsageSnapshotCacheStore.saveCodex(snapshot, to: directoryURL)
        let loaded = UsageSnapshotCacheStore.loadCodex(from: directoryURL)

        XCTAssertEqual(loaded, snapshot.quotaOnlyProjection)
        XCTAssertEqual(loaded?.sourceFilePath, "")
        XCTAssertNil(loaded?.planType)
        XCTAssertNil(loaded?.limitID)
        XCTAssertNil(loaded?.tokenUsage)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: directoryURL.appendingPathComponent("codex-usage.json").path
        )
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
    }

    func testSaveAndLoadCursorSnapshotContainsNoCredentialFields() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-island-usage-cache-cursor-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let snapshot = CursorUsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
            planName: "Pro",
            billingCycleEnd: Date(timeIntervalSince1970: 1_787_199_156),
            totalSpendCents: 8_007,
            includedSpendCents: 2_000,
            bonusSpendCents: 6_007,
            limitCents: 2_000,
            totalUsedPercentage: 23.2,
            apiUsedPercentage: 100,
            autoUsedPercentage: 10.07
        )

        UsageSnapshotCacheStore.saveCursor(snapshot, to: directoryURL)
        XCTAssertEqual(UsageSnapshotCacheStore.loadCursor(from: directoryURL), snapshot)

        let fileURL = directoryURL.appendingPathComponent("cursor-usage.json")
        let cacheText = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(cacheText.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(cacheText.localizedCaseInsensitiveContains("authorization"))
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
    }
}
