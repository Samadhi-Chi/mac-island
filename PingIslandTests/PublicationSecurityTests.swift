import Darwin
import Foundation
import XCTest

@testable import Ping_Island

@MainActor
final class PublicationSecurityTests: XCTestCase {
    func testUntrustedNumbersCannotTrapOrInventDates() {
        for value in [Double.nan, .infinity, -.infinity, 1e200, -1e200] {
            XCTAssertNil(ObservedNumber.integer(value))
            XCTAssertNil(ObservedNumber.percentage(value))
            XCTAssertNil(ObservedNumber.unixDate(value))
            XCTAssertEqual(UsageSummaryPresenter.valueText(for: value, mode: .used), "—")
            XCTAssertEqual(SessionPhaseHelpers.timeAgo(Date(timeIntervalSince1970: value)), "—")
        }
        XCTAssertEqual(ObservedNumber.integer("123"), 123)
        XCTAssertEqual(ObservedNumber.percentage(125), 125)
        XCTAssertNotNil(ObservedNumber.unixDate(1_800_000_000))
        XCTAssertEqual(ObservedNumber.sum(.max, .max), .max)
    }

    func testQuotaAliasesAndOldCachesRejectUnsafePercentages() throws {
        for key in ["usedPercent", "used_percent"] {
            for badValue in [-1e100, 1e100, -1.0] {
                XCTAssertNil(
                    CodexUsageLoader.snapshotFromAppServerRateLimits([
                        "primary": [key: badValue, "windowDurationMins": 300]
                    ]))
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bad = CodexUsageSnapshot(
            sourceFilePath: "", capturedAt: Date(), planType: nil, limitID: nil,
            windows: [
                .init(
                    key: "primary", label: "5h", usedPercentage: -1e100,
                    leftPercentage: 1e100, windowMinutes: 300, resetsAt: nil)
            ])
        UsageSnapshotCacheStore.saveCodex(bad, to: directory)
        XCTAssertNil(UsageSnapshotCacheStore.loadCodex(from: directory))
    }

    func testEphemeralPreferencesHaveNoPersistentDomain() throws {
        let domain = "MacIsland.test." + UUID().uuidString
        let defaults = try XCTUnwrap(MacIslandEphemeralDefaults(suiteName: domain))
        defaults.set(true, forKey: "flag")
        defaults.set(42, forKey: "count")
        defaults.set("synthetic", forKey: "name")
        XCTAssertTrue(defaults.bool(forKey: "flag"))
        XCTAssertEqual(defaults.integer(forKey: "count"), 42)
        XCTAssertEqual(defaults.string(forKey: "name"), "synthetic")
        XCTAssertTrue(UserDefaults.standard.persistentDomain(forName: domain)?.isEmpty ?? true)
    }

    func testIsolatedModesAllCloseTheLiveIOBoundary() {
        for environment in [
            ["XCTestConfigurationFilePath": "fixture"], ["PING_ISLAND_UI_TEST_MODE": "1"],
            ["MAC_ISLAND_UI_TEST_MODE": "1"], ["MAC_ISLAND_FIXTURE_PATH": "/synthetic/fixture.json"],
        ] {
            XCTAssertFalse(MacIslandRuntimeEnvironment.allowsLiveIO(environment: environment, hasXCTestRuntime: false))
        }
        XCTAssertTrue(MacIslandRuntimeEnvironment.allowsLiveIO(environment: [:], hasXCTestRuntime: false))
    }

    func testCursorNetworkLookupFailsBeforeReadingCredentials() async {
        do {
            _ = try await CursorUsageLoader.load(databaseURL: URL(fileURLWithPath: "/synthetic/nonexistent"))
            XCTFail("monitor-only app attempted a credential-backed quota request")
        } catch { XCTAssertEqual(error as? CursorUsageLoaderError, .networkDisabled) }
    }

    func testRolloutRequiresExactIdentityAndAllowedRegularFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let file = root.appendingPathComponent("rollout-matching.jsonl")
        let content =
            #"{"type":"session_meta","payload":{"id":"matching","source":"cli","cwd":"/synthetic"}}"# + "\n"
            + #"{"type":"event_msg","payload":{"type":"agent_message","message":"Synthetic reply","phase":"final"}}"#
            + "\n"
        try content.write(to: file, atomically: true, encoding: .utf8)
        try content.write(to: outside, atomically: true, encoding: .utf8)
        let parser = CodexRolloutParser(sessionsRoot: root)
        func info(_ path: URL) -> SessionClientInfo {
            SessionClientInfo(kind: .codexApp, sessionFilePath: path.path)
        }
        let valid = await parser.parseThread(threadId: "matching", fallbackCwd: "/synthetic", clientInfo: info(file))
        XCTAssertNotNil(valid)
        let mismatch = await parser.parseThread(threadId: "other", fallbackCwd: "/synthetic", clientInfo: info(file))
        XCTAssertNil(mismatch)
        let escaped = await parser.parseThread(
            threadId: "matching", fallbackCwd: "/synthetic", clientInfo: info(outside))
        XCTAssertNil(escaped)
        let link = root.appendingPathComponent("link.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertNil(BoundedLocalFileReader.jsonl(at: link, under: root))
        let fifo = root.appendingPathComponent("pipe.jsonl")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertNil(BoundedLocalFileReader.jsonl(at: fifo, under: root))
        let huge = root.appendingPathComponent("huge.jsonl")
        try (content + String(repeating: "x", count: 5 * 1024 * 1024)).write(
            to: huge, atomically: true, encoding: .utf8)
        XCTAssertNil(BoundedLocalFileReader.jsonl(at: huge, under: root))
    }

    func testStdioReadsFragmentedFramesAndRejectsOversizedFrame() async throws {
        let input = Pipe()
        let output = Pipe()
        let transport = CodexStdioTransport(
            input: input.fileHandleForWriting, output: output.fileHandleForReading, maximumBytes: 128)
        transport.resume()
        defer { transport.cancel(with: .goingAway, reason: nil) }
        try output.fileHandleForWriting.write(contentsOf: Data(#"{"id":"ok""#.utf8))
        try output.fileHandleForWriting.write(contentsOf: Data("}\n".utf8))
        let message = try await transport.receive()
        guard case .data(let bytes) = message else { return XCTFail("expected a JSONL frame") }
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), #"{"id":"ok"}"#)
        try output.fileHandleForWriting.write(contentsOf: Data(repeating: 120, count: 129))
        do {
            _ = try await transport.receive()
            XCTFail("oversized frame accepted")
        } catch {}
    }

    func testTerminalSelectorsRemainAppleScriptLiterals() {
        let injected = "bad\" & do shell script \"echo synthetic\" & \""
        let script = TerminalSessionFocuser.iTermSelectionScriptLinesForTesting(
            tty: injected, sessionIdentifier: injected
        ).joined(separator: "\n")
        XCTAssertFalse(script.contains("is \"" + injected + "\" then"))
        XCTAssertTrue(script.contains(#"bad\" & do shell script"#))
    }

    func testHugeDiffPreviewDoesNotAllocateAnUnboundedMatrix() {
        let old = String(repeating: "old\n", count: 20_000)
        let new = String(repeating: "new\n", count: 20_000)
        _ = SimpleDiffView(oldString: old, newString: new)
        _ = SimpleDiffView(oldString: "line\nold", newString: "line\nnew")
    }
}
