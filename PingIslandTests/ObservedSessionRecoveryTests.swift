import Foundation
import XCTest

@testable import Ping_Island

final class ObservedSessionRecoveryTests: XCTestCase {
    func testOpenCodeRecoveryReadsOnlyRecentParentMetadata() throws {
        let root = temporaryRoot()
        let databaseURL = root.appendingPathComponent("opencode.db")
        defer { try? FileManager.default.removeItem(at: root) }
        try createDatabase(
            at: databaseURL,
            sql: """
                CREATE TABLE session (
                  id TEXT PRIMARY KEY,
                  parent_id TEXT,
                  directory TEXT NOT NULL,
                  title TEXT NOT NULL,
                  model TEXT,
                  time_updated INTEGER NOT NULL
                );
                INSERT INTO session VALUES (
                  'recent-parent', NULL, '/tmp/open-code', 'Fix release',
                  '{"id":"gpt-5.6-sol","providerID":"openai"}', 1799999999000
                );
                INSERT INTO session VALUES (
                  'recent-child', 'recent-parent', '/tmp/open-code', 'Child',
                  '{"id":"gpt-5.6-sol","providerID":"openai"}', 1799999999500
                );
                INSERT INTO session VALUES (
                  'old-parent', NULL, '/tmp/old', 'Old', NULL, 1799990000000
                );
                """
        )

        let recovered = ObservedSessionRecovery.loadOpenCode(
            databaseURL: databaseURL,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].nativeSessionID, "recent-parent")
        XCTAssertEqual(recovered[0].origin, .unknown)
        XCTAssertEqual(recovered[0].nativeTitle, "Fix release")
        XCTAssertEqual(recovered[0].serviceProvider, "openai")
        XCTAssertEqual(recovered[0].modelName, "gpt-5.6-sol")
        XCTAssertNil(recovered[0].clientInfo.bundleIdentifier)
        XCTAssertTrue(recovered[0].clientInfo.suppressesActivationNavigation)
        XCTAssertEqual(recovered[0].sessionID, "observed:opencode:unknown:recent-parent")
        XCTAssertTrue(
            MacIslandProductPolicy.supportsSession(
                provider: .claude, clientInfo: recovered[0].clientInfo
            ))
    }

    func testHermesRecoveryExcludesCronAndChildRows() throws {
        let root = temporaryRoot()
        let databaseURL = root.appendingPathComponent("state.db")
        defer { try? FileManager.default.removeItem(at: root) }
        try createDatabase(
            at: databaseURL,
            sql: """
                CREATE TABLE sessions (
                  id TEXT PRIMARY KEY,
                  source TEXT NOT NULL,
                  model TEXT,
                  billing_provider TEXT,
                  title TEXT,
                  cwd TEXT,
                  started_at REAL NOT NULL,
                  last_activity_at REAL,
                  parent_session_id TEXT
                );
                INSERT INTO sessions VALUES (
                  'desktop-parent', 'desktop', 'gpt-5.6-sol', 'openai-codex',
                  'Release review', '/tmp/hermes', 1799999900, 1799999999, NULL
                );
                INSERT INTO sessions VALUES (
                  'desktop-child', 'desktop', 'gpt-5.6-sol', 'openai-codex',
                  'Worker', '/tmp/hermes', 1799999950, 1799999999, 'desktop-parent'
                );
                INSERT INTO sessions VALUES (
                  'cron-task', 'cron', 'gpt-5.6-sol', 'openai-codex',
                  'Maintenance', '/tmp/hermes', 1799999950, 1799999999, NULL
                );
                """
        )

        let recovered = ObservedSessionRecovery.loadHermes(
            databaseURL: databaseURL,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].nativeSessionID, "desktop-parent")
        XCTAssertEqual(recovered[0].origin, .desktop)
        XCTAssertEqual(recovered[0].serviceProvider, "openai-codex")
        XCTAssertEqual(recovered[0].clientInfo.bundleIdentifier, "com.nousresearch.hermes.setup")
    }

    func testSchemaChangeDisablesRecoveryWithoutGuessing() throws {
        let root = temporaryRoot()
        let databaseURL = root.appendingPathComponent("changed.db")
        defer { try? FileManager.default.removeItem(at: root) }
        try createDatabase(at: databaseURL, sql: "CREATE TABLE session (id TEXT PRIMARY KEY);")

        XCTAssertTrue(
            ObservedSessionRecovery.loadOpenCode(databaseURL: databaseURL).isEmpty
        )
    }

    func testHermesEffectiveTimestampControlsSelectionOrderingAndRestoredActivity() throws {
        let root = temporaryRoot()
        let databaseURL = root.appendingPathComponent("state.db")
        defer { try? FileManager.default.removeItem(at: root) }
        try createDatabase(
            at: databaseURL,
            sql: """
                CREATE TABLE sessions (
                  id TEXT PRIMARY KEY, source TEXT NOT NULL, model TEXT, billing_provider TEXT,
                  title TEXT, cwd TEXT, started_at REAL NOT NULL, last_activity_at REAL,
                  parent_session_id TEXT
                );
                INSERT INTO sessions VALUES
                  ('null-recent', 'desktop', NULL, NULL, NULL, '/tmp/hermes', 1799999990, NULL, NULL),
                  ('activity-recent', 'cli', NULL, NULL, NULL, '/tmp/hermes', 1799999995, 1799999980, NULL),
                  ('boundary', 'cli', NULL, NULL, NULL, '/tmp/hermes', 1799998200, NULL, NULL),
                  ('null-old', 'desktop', NULL, NULL, NULL, '/tmp/hermes', 1799998199, NULL, NULL),
                  ('activity-old', 'cli', NULL, NULL, NULL, '/tmp/hermes', 1799999999, 1799998199, NULL),
                  ('null-child', 'desktop', NULL, NULL, NULL, '/tmp/hermes', 1799999999, NULL, 'null-recent'),
                  ('gateway', 'gateway', NULL, NULL, NULL, '/tmp/hermes', 1799999999, NULL, NULL);
                """)

        let recovered = ObservedSessionRecovery.loadHermes(
            databaseURL: databaseURL, now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertEqual(recovered.map(\.nativeSessionID), ["null-recent", "activity-recent", "boundary"])
        XCTAssertEqual(
            recovered.map { $0.lastActivity.timeIntervalSince1970 },
            [
                1_799_999_990, 1_799_999_980, 1_799_998_200,
            ])
    }

    func testHermesMissingRequiredColumnDisablesRecovery() throws {
        let root = temporaryRoot()
        let databaseURL = root.appendingPathComponent("changed-hermes.db")
        defer { try? FileManager.default.removeItem(at: root) }
        try createDatabase(
            at: databaseURL,
            sql: """
                CREATE TABLE sessions (
                  id TEXT, source TEXT, model TEXT, billing_provider TEXT, title TEXT,
                  cwd TEXT, started_at REAL, parent_session_id TEXT
                );
                INSERT INTO sessions VALUES ('recent', 'desktop', NULL, NULL, NULL, '/tmp/hermes', 1799999999, NULL);
                """)
        XCTAssertTrue(
            ObservedSessionRecovery.loadHermes(
                databaseURL: databaseURL, now: Date(timeIntervalSince1970: 1_800_000_000)
            ).isEmpty)
    }

    func testOpenCodeRecoveryOrdersAndBoundsRecentParents() throws {
        let root = temporaryRoot()
        let databaseURL = root.appendingPathComponent("opencode.db")
        defer { try? FileManager.default.removeItem(at: root) }
        let inserts = (0..<25).map { index in
            "INSERT INTO session VALUES ('session-\(index)', NULL, '/tmp/opencode', NULL, NULL, \(1_800_000_000_000 - index * 1000));"
        }.joined(separator: "\n")
        try createDatabase(
            at: databaseURL,
            sql: """
                CREATE TABLE session (id TEXT, parent_id TEXT, directory TEXT, title TEXT, model TEXT, time_updated INTEGER);
                \(inserts)
                """)
        let recovered = ObservedSessionRecovery.loadOpenCode(
            databaseURL: databaseURL, now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertEqual(recovered.map(\.nativeSessionID), (0..<20).map { "session-\($0)" })
        XCTAssertTrue(recovered.allSatisfy { $0.origin == .unknown })
    }

    func testLiveOpenCodeEventConsumesUnknownRecoveryAndKeepsMetadata() async throws {
        let nativeID = "recovered-\(UUID().uuidString)"
        let recovered = recoveredOpenCode(nativeID: nativeID)
        let liveEvent = openCodeEvent(nativeID: nativeID, origin: .desktop, event: "SessionStart")
        let store = SessionStore.shared
        await store.restoreObservedSessions([recovered])
        await store.restoreObservedSessions([recovered])
        let before = await store.session(for: recovered.sessionID)
        XCTAssertEqual(before?.phase, .idle)
        XCTAssertTrue(before?.clientInfo.suppressesActivationNavigation == true)
        XCTAssertTrue(before?.chatItems.isEmpty == true)

        await store.process(.hookReceived(liveEvent))
        let unknown = await store.session(for: recovered.sessionID)
        let live = await store.session(for: liveEvent.sessionId)
        XCTAssertNil(unknown)
        XCTAssertEqual(live?.sessionId, "observed:opencode:desktop:\(nativeID)")
        XCTAssertEqual(live?.sessionName, recovered.nativeTitle)
        XCTAssertEqual(live?.modelName, recovered.modelName)
        XCTAssertEqual(live?.serviceProviderName, recovered.serviceProvider)
        XCTAssertEqual(live?.cwd, "/tmp/live-project")
        XCTAssertEqual(live?.clientInfo.origin, "desktop")
        XCTAssertEqual(live?.clientInfo.threadSource, "opencode-plugin")
        XCTAssertFalse(live?.clientInfo.suppressesActivationNavigation ?? true)
        XCTAssertEqual(live?.phase, .processing)
        XCTAssertGreaterThan(try XCTUnwrap(live?.lastActivity), recovered.lastActivity)
        await store.process(.sessionArchived(sessionId: liveEvent.sessionId))
    }

    func testLateUnknownRecoveryDoesNotReplaceLiveMetadataOrAddDuplicate() async {
        let nativeID = "live-first-\(UUID().uuidString)"
        let recovered = recoveredOpenCode(nativeID: nativeID)
        let event = openCodeEvent(nativeID: nativeID, origin: .cli, nativeTitle: "Live title", model: "live-model")
        let store = SessionStore.shared
        await store.process(.hookReceived(event))
        let before = await store.session(for: event.sessionId)
        await store.restoreObservedSessions([recovered])
        let after = await store.session(for: event.sessionId)
        let unknown = await store.session(for: recovered.sessionID)
        XCTAssertNil(unknown)
        XCTAssertEqual(after, before)
        XCTAssertEqual(after?.sessionName, "Live title")
        XCTAssertEqual(after?.modelName, "live-model")
        await store.process(.sessionArchived(sessionId: event.sessionId))
    }

    func testKnownOpenCodeOriginsStaySeparateAfterRecoveryAndRepeatedEvents() async {
        let nativeID = "both-surfaces-\(UUID().uuidString)"
        let recovered = recoveredOpenCode(nativeID: nativeID)
        let cliEvent = openCodeEvent(nativeID: nativeID, origin: .cli, nativeTitle: "CLI title")
        let desktopEvent = openCodeEvent(nativeID: nativeID, origin: .desktop, nativeTitle: "Desktop title")
        let store = SessionStore.shared
        await store.restoreObservedSessions([recovered])
        await store.process(.hookReceived(cliEvent))
        await store.process(.hookReceived(desktopEvent))
        await store.process(.hookReceived(cliEvent))
        await store.restoreObservedSessions([recovered])

        let cli = await store.session(for: cliEvent.sessionId)
        let desktop = await store.session(for: desktopEvent.sessionId)
        let unknown = await store.session(for: recovered.sessionID)
        XCTAssertNil(unknown)
        XCTAssertEqual(cli?.sessionName, "CLI title")
        XCTAssertEqual(desktop?.sessionName, "Desktop title")
        XCTAssertEqual(cli?.clientInfo.origin, "cli")
        XCTAssertEqual(desktop?.clientInfo.origin, "desktop")
        await store.process(.sessionArchived(sessionId: cliEvent.sessionId))
        await store.process(.sessionArchived(sessionId: desktopEvent.sessionId))
    }

    func testUnknownOriginCannotNavigateEvenWithStaleRoutingHints() {
        var client = recoveredOpenCode(nativeID: "unknown-route").clientInfo
        client.bundleIdentifier = "ai.opencode.desktop"
        client.launchURL = "opencode://session/unknown-route"
        client.terminalBundleIdentifier = "com.apple.Terminal"
        XCTAssertTrue(client.suppressesActivationNavigation)
        client.origin = "cli"
        XCTAssertFalse(client.suppressesActivationNavigation)
        client.origin = "unknown"
        client.threadSource = "opencode-plugin"
        XCTAssertFalse(MacIslandProductPolicy.supportsSession(provider: .claude, clientInfo: client))
    }

    func testDistinctNativeIDsInOneWorkspaceAreNotOrphans() async {
        let first = openCodeEvent(nativeID: "first-\(UUID().uuidString)", origin: .cli)
        let second = openCodeEvent(nativeID: "second-\(UUID().uuidString)", origin: .cli)
        let store = SessionStore.shared
        await store.process(.hookReceived(first))
        await store.process(.hookReceived(second))
        let firstSession = await store.session(for: first.sessionId)
        let secondSession = await store.session(for: second.sessionId)
        XCTAssertNotNil(firstSession)
        XCTAssertNotNil(secondSession)
        await store.process(.sessionArchived(sessionId: first.sessionId))
        await store.process(.sessionArchived(sessionId: second.sessionId))
    }

    private func recoveredOpenCode(nativeID: String) -> ObservedRecoveredSession {
        ObservedRecoveredSession(
            nativeSessionID: nativeID, client: .openCode, origin: .unknown,
            cwd: "/tmp/recovered-project", nativeTitle: "Recovered title",
            serviceProvider: "recovered-provider", modelName: "recovered-model",
            lastActivity: Date().addingTimeInterval(-60)
        )
    }

    private func openCodeEvent(
        nativeID: String, origin: MacIslandSessionOrigin,
        event: String = "UserPromptSubmit", nativeTitle: String? = nil, model: String? = nil
    ) -> HookEvent {
        var client = recoveredOpenCode(nativeID: nativeID).clientInfo
        client.origin = origin.rawValue
        client.threadSource = "opencode-plugin"
        return HookEvent(
            sessionId: MacIslandProductPolicy.observedSessionKey(nativeSessionID: nativeID, clientInfo: client),
            cwd: "/tmp/live-project", event: event, status: "processing", provider: .claude,
            clientInfo: client, pid: nil, tty: nil, tool: nil, toolInput: nil,
            toolUseId: nil, notificationType: nil, message: nil,
            nativeTitle: nativeTitle, modelName: model, nativeSessionId: nativeID,
            suppressInAppPrompt: true
        )
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-island-recovery-\(UUID().uuidString)", isDirectory: true)
    }

    private func createDatabase(at databaseURL: URL, sql: String) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databaseURL.path, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
