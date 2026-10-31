import Foundation
import XCTest

@testable import Ping_Island

@MainActor
final class RecentSessionIndexTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRetentionCapsOrdersAndExpiresRecords() {
        let index = RecentSessionIndex(fileURL: nil, now: { self.now })
        index.ingest((0..<220).map { record("id-\($0)", age: Double($0)) } + [record("expired", age: 8 * 86_400)])
        XCTAssertEqual(index.records.count, 200)
        XCTAssertEqual(index.records.first?.nativeSessionID, "id-0")
        XCTAssertFalse(index.records.contains { $0.nativeSessionID == "expired" })
        index.setRetention(.day)
        XCTAssertEqual(index.records.count, 100)
        index.ingest([record("day-old", age: 86_401)])
        XCTAssertFalse(index.records.contains { $0.nativeSessionID == "day-old" })
    }

    func testRoundTripContainsOnlyAllowlistedMetadata() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("recent.json")
        let index = RecentSessionIndex(fileURL: file, now: { self.now })
        let session = SessionState(
            sessionId: "private-content-test", cwd: "/tmp/sample-project",
            provider: .codex, sessionName: "sensitive-title",
            previewText: "sensitive-reply", latestHookMessage: "sensitive-prompt",
            lastActivity: now)
        index.observe([session])
        index.persistNow()
        let json = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(json.contains("sensitive-"))
        XCTAssertFalse(json.contains("sessionName"))
        XCTAssertFalse(json.contains("launchURL"))
        XCTAssertFalse(json.contains("pid"))
        let restored = RecentSessionIndex(fileURL: file, now: { self.now })
        XCTAssertEqual(restored.records, index.records)
    }

    func testSessionOnlyRemovesFileAndCancelsQueuedWrite() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("recent.json")
        let index = RecentSessionIndex(fileURL: file, now: { self.now })
        index.ingest([record("kept-in-memory")])
        index.persistNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        index.setRetention(.sessionOnly)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(index.records.count, 1)
        index.setRetention(.disabled)
        index.ingest([record("must-not-record")])
        XCTAssertTrue(index.records.isEmpty)
    }

    func testClearDoesNotReimportUnchangedNativeHistoryAfterRelaunch() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("recent.json")
        let index = RecentSessionIndex(fileURL: file, now: { self.now })
        index.ingest([record("before-clear", age: 20)])
        index.clear()
        let restored = RecentSessionIndex(fileURL: file, now: { self.now.addingTimeInterval(10) })
        restored.ingest([record("before-clear", age: 20), record("new-event", age: -5)])
        XCTAssertEqual(restored.records.map(\.nativeSessionID), ["new-event"])
    }

    func testCorruptOrUnsupportedEnvelopeStartsEmpty() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("recent.json")
        for text in ["invalid-json", "{\"version\":999,\"records\":[]}"] {
            try Data(text.utf8).write(to: file)
            let index = RecentSessionIndex(fileURL: file, now: { self.now })
            XCTAssertTrue(index.records.isEmpty)
            XCTAssertNotNil(index.storageMessage)
            index.ingest([record("fresh")])
            index.persistNow()
            XCTAssertNil(index.storageMessage)
        }
    }

    func testKnownOriginReplacesUnknownWithoutMergingCLIAndDesktop() {
        let index = RecentSessionIndex(fileURL: nil, now: { self.now })
        index.ingest([record("same", origin: "unknown")])
        index.ingest([record("same", origin: "cli"), record("same", origin: "desktop")])
        index.ingest([record("same", origin: "unknown", age: -1)])
        XCTAssertEqual(Set(index.records.map(\.origin)), ["cli", "desktop"])
    }

    func testDeduplicationKeepsNewerRecordAndDropsInvalidFutureData() {
        let index = RecentSessionIndex(fileURL: nil, now: { self.now })
        index.ingest([record("same", age: 10), record("same", age: 100), record("future", age: -3_600)])
        XCTAssertEqual(index.records.count, 1)
        XCTAssertEqual(index.records.first?.lastActivity, now.addingTimeInterval(-10))
    }

    func testNativeIdentityStripsExactlyOneProductNamespace() throws {
        let info = SessionClientInfo(kind: .custom, profileID: "hermes", name: "Hermes", origin: "desktop")
        let native = "observed:inside-native-id"
        let session = SessionState(
            sessionId: MacIslandProductPolicy.observedSessionKey(nativeSessionID: native, clientInfo: info),
            cwd: "/tmp/example", provider: .claude, clientInfo: info, lastActivity: now)
        let entry = try XCTUnwrap(RecentSessionRecord(session: session))
        XCTAssertEqual(entry.nativeSessionID, native)
        XCTAssertNil(entry.navigationSession.pid)
        XCTAssertNil(entry.navigationSession.tty)
        XCTAssertEqual(entry.navigationSession.clientInfo.bundleIdentifier, "com.nousresearch.hermes.setup")
        XCTAssertEqual(SessionNavigationIdentity.nativeSessionID(for: entry.navigationSession), native)
    }

    func testMaintenancePrunesWithoutNewActivity() {
        var clock = now
        let index = RecentSessionIndex(fileURL: nil, retention: .day, now: { clock })
        index.ingest([record("expires")])
        clock = clock.addingTimeInterval(86_401)
        index.prune()
        XCTAssertTrue(index.records.isEmpty)
    }

    func testReenableStartsAfterDisabledPeriodInsteadOfReimportingOldSnapshots() {
        var clock = now
        let index = RecentSessionIndex(fileURL: nil, now: { clock })
        index.ingest([record("before")])
        index.setRetention(.disabled)
        clock = clock.addingTimeInterval(50)
        index.setRetention(.week)
        index.ingest([record("before"), record("while-disabled", age: -25), record("after", age: -51)])
        XCTAssertEqual(index.records.map(\.nativeSessionID), ["after"])
    }

    func testNonpersistentLaunchDeletesPriorFileWithoutLoadingIt() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("recent.json")
        let original = RecentSessionIndex(fileURL: file, now: { self.now })
        original.ingest([record("old")])
        original.persistNow()
        original.setRetention(.sessionOnly)
        try Data("private-old-content".utf8).write(to: file)
        let restarted = RecentSessionIndex(fileURL: file, retention: .disabled, now: { self.now })
        XCTAssertTrue(restarted.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testMissingMultiSurfaceOriginStaysUnknownAndDoesNotCreateDesktopTarget() throws {
        let info = SessionClientInfo(kind: .custom, profileID: "hermes", name: "Hermes")
        let session = SessionState(
            sessionId: "hermes-unknown", cwd: "/tmp/example", clientInfo: info, lastActivity: now)
        let entry = try XCTUnwrap(RecentSessionRecord(session: session))
        XCTAssertEqual(entry.origin, "unknown")
        XCTAssertNil(entry.navigationSession.clientInfo.bundleIdentifier)
        XCTAssertNil(entry.navigationSession.clientInfo.launchURL)
    }

    func testInvalidWorkspaceAndChildSnapshotsAreNotRecorded() {
        let index = RecentSessionIndex(fileURL: nil, now: { self.now })
        index.ingest([
            RecentSessionRecord(
                sessionID: "invalid", nativeSessionID: "invalid", client: .codexDesktop,
                origin: "desktop", workspace: "relative/path", lastActivity: now)
        ])
        let child = SessionState(
            sessionId: "child", cwd: "/tmp/example", provider: .codex,
            codexParentThreadId: "parent", lastActivity: now)
        index.observe([child])
        XCTAssertTrue(index.records.isEmpty)
    }

    func testClearRejectsUnchangedObservationButAcceptsLaterActivity() {
        let index = RecentSessionIndex(fileURL: nil, now: { self.now })
        var session = SessionState(sessionId: "observed", cwd: "/tmp/example", provider: .codex, lastActivity: now)
        index.observe([session])
        index.clear()
        index.observe([session])
        XCTAssertTrue(index.records.isEmpty)
        session.lastActivity = now.addingTimeInterval(1)
        index.observe([session])
        XCTAssertEqual(index.records.count, 1)
    }

    func testClearWatermarkIncludesClockSkewAcrossObservationAndRelaunch() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("recent.json")
        let index = RecentSessionIndex(fileURL: file, now: { self.now })
        var session = SessionState(
            sessionId: "skewed", cwd: "/tmp/example", provider: .codex,
            lastActivity: now.addingTimeInterval(30))
        index.observe([session])
        XCTAssertEqual(index.records.count, 1)
        index.clear()
        index.observe([session])
        XCTAssertTrue(index.records.isEmpty)
        let restored = RecentSessionIndex(fileURL: file, now: { self.now.addingTimeInterval(1) })
        restored.observe([session])
        XCTAssertTrue(restored.records.isEmpty)
        session.lastActivity = now.addingTimeInterval(31)
        restored.observe([session])
        XCTAssertEqual(restored.records.count, 1)
    }

    func testDisableReenablePreservesClockSkewWatermarkAndRemovesFile() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("recent.json")
        let index = RecentSessionIndex(fileURL: file, now: { self.now })
        index.ingest([record("skewed", age: -30)])
        index.persistNow()
        index.setRetention(.disabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        index.setRetention(.week)
        index.ingest([record("skewed", age: -30)])
        XCTAssertTrue(index.records.isEmpty)
        let restored = RecentSessionIndex(fileURL: file, now: { self.now.addingTimeInterval(1) })
        restored.ingest([record("skewed", age: -30)])
        XCTAssertTrue(restored.records.isEmpty)
        restored.ingest([record("skewed", age: -31)])
        XCTAssertEqual(restored.records.count, 1)
    }

    func testCursorLocalObservationNormalizesOriginAndPreservesNativeID() throws {
        // Match SessionStore.syncCursorConversationSnapshot's actual ingress.
        let info = SessionClientInfo(
            kind: .custom, profileID: "cursor-local", name: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92", origin: "cursor-local")
        let session = SessionState(
            sessionId: "composer-id", cwd: "/tmp/example", provider: .claude,
            clientInfo: info, ingress: .desktopAppMonitor, lastActivity: now)
        let index = RecentSessionIndex(fileURL: nil, now: { self.now })
        index.observe([session])
        let entry = try XCTUnwrap(index.records.first)
        XCTAssertEqual(entry.client, .cursor)
        XCTAssertEqual(entry.origin, "desktop")
        XCTAssertEqual(entry.nativeSessionID, "composer-id")
        XCTAssertEqual(entry.navigationSession.clientInfo.bundleIdentifier, info.bundleIdentifier)
        XCTAssertNotNil(entry.navigationSession.clientInfo.launchURL)
        XCTAssertEqual(SessionNavigationIdentity.nativeSessionID(for: entry.navigationSession), "composer-id")
    }

    func testUnrecognizedOriginRemainsInformationalMetadata() throws {
        let info = SessionClientInfo(kind: .codexApp, profileID: "codex-app", name: "Codex", origin: "future-source")
        let session = SessionState(
            sessionId: "future-source-id", cwd: "/tmp/example", provider: .codex,
            clientInfo: info, lastActivity: now)
        let entry = try XCTUnwrap(RecentSessionRecord(session: session))
        XCTAssertEqual(entry.origin, "unknown")
        XCTAssertNil(entry.navigationSession.clientInfo.launchURL)
    }

    private func record(_ id: String, origin: String = "cli", age: TimeInterval = 0) -> RecentSessionRecord {
        RecentSessionRecord(
            sessionID: "observed:opencode:\(origin):\(id)", nativeSessionID: id,
            client: .openCode, origin: origin, workspace: "/tmp/example",
            lastActivity: now.addingTimeInterval(-age))
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("recent-index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
