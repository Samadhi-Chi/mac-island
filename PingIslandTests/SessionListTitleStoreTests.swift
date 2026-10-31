import XCTest

@testable import Ping_Island

@MainActor
final class SessionListTitleStoreTests: XCTestCase {
    func testNativeTitleDoesNotSubstituteDirectorySummaryOrPrompt() {
        let store = SessionListTitleStore()
        var session = fixture("one")
        session.conversationInfo = ConversationInfo(
            summary: "Generated summary", lastMessage: nil,
            lastMessageRole: nil, lastToolName: nil,
            firstUserMessage: "First prompt", lastUserMessageDate: nil)
        XCTAssertEqual(store.title(for: session), .unavailable)
        session.sessionName = "Original  title · 项目"
        XCTAssertEqual(store.title(for: session), .native("Original  title · 项目"))
        session.sessionName = " \n "
        XCTAssertEqual(store.title(for: session), .unavailable)
    }

    func testReadTitleIsSharedWithHistoryAndLiveRenameWinsOverDelayedResult() async throws {
        let started = expectation(description: "metadata read")
        let reader = DelayedTitleReader(onStart: { started.fulfill() })
        let store = SessionListTitleStore(reader: { try await reader.read($0) })
        var session = fixture("rename")
        session.sessionName = "Before rename"
        let record = try XCTUnwrap(RecentSessionRecord(session: session))
        let task = Task { await store.refresh(records: [record], observedSessions: [session]) }
        await fulfillment(of: [started], timeout: 3)
        session.sessionName = "Renamed in client"
        await reader.finish(record.id, name: "Older server result")
        await task.value
        XCTAssertEqual(store.title(for: session), .native("Renamed in client"))
        XCTAssertEqual(store.title(for: record, observedSession: session), store.title(for: session))
    }

    func testHistoricalNativeNameRefreshesAndFailureCannotInventAName() async throws {
        let reader = TitleResponses()
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let store = SessionListTitleStore(reader: { try await reader.read($0) }, now: { clock })
        let record = try XCTUnwrap(RecentSessionRecord(session: fixture("history")))
        await reader.set("First name")
        await store.refresh(records: [record], observedSessions: [])
        XCTAssertEqual(store.title(for: record, observedSession: nil), .native("First name"))
        await reader.set("Renamed name")
        await store.refresh(records: [record], observedSessions: [])
        let initialReads = await reader.count
        XCTAssertEqual(initialReads, 1)
        clock = clock.addingTimeInterval(31)
        await store.refresh(records: [record], observedSessions: [])
        XCTAssertEqual(store.title(for: record, observedSession: nil), .native("Renamed name"))
        clock = clock.addingTimeInterval(31)
        await reader.set(nil)
        await store.refresh(records: [record], observedSessions: [])
        XCTAssertEqual(store.title(for: record, observedSession: nil), .unavailable)
    }

    func testSupersededReadCannotRestoreClearedRecords() async throws {
        let started = expectation(description: "old batch")
        let reader = DelayedTitleReader(onStart: { started.fulfill() })
        let store = SessionListTitleStore(reader: { try await reader.read($0) })
        let record = try XCTUnwrap(RecentSessionRecord(session: fixture("cleared")))
        let task = Task { await store.refresh(records: [record], observedSessions: []) }
        await fulfillment(of: [started], timeout: 3)
        await store.refresh(records: [], observedSessions: [])
        await reader.finish(record.id, name: "Late private name")
        await task.value
        XCTAssertEqual(store.title(for: record, observedSession: nil), .unavailable)
    }

    func testMetadataBatchBoundsOutstandingReads() async throws {
        let firstFour = expectation(description: "four outstanding reads")
        let reader = BoundedTitleReader(firstFour: firstFour)
        let store = SessionListTitleStore(reader: { await reader.read($0) })
        let records = (0..<9).compactMap { RecentSessionRecord(session: fixture("batch-\($0)")) }
        let task = Task { await store.refresh(records: records, observedSessions: []) }
        await fulfillment(of: [firstFour], timeout: 3)
        let beforeRelease = await reader.started
        XCTAssertEqual(beforeRelease, 4)
        await reader.release()
        await task.value
        let maximum = await reader.maximumOutstanding
        let finalCount = await reader.started
        XCTAssertLessThanOrEqual(maximum, 4)
        XCTAssertEqual(finalCount, records.count)
        for record in records {
            XCTAssertEqual(store.title(for: record, observedSession: nil), .native("Native title"))
        }
    }

    func testLookupRequiresExactClientAndOriginAndSkipsNonCodexRecords() async throws {
        let reader = TitleResponses()
        let store = SessionListTitleStore(reader: { try await reader.read($0) })
        let session = fixture("shared")
        let desktop = try XCTUnwrap(RecentSessionRecord(session: session))
        let cli = RecentSessionRecord(
            sessionID: "observed:codex:cli:shared", nativeSessionID: "shared",
            client: .codexCLI, origin: "cli", workspace: session.cwd,
            lastActivity: session.lastActivity)
        let cursor = RecentSessionRecord(
            sessionID: "cursor", nativeSessionID: "shared", client: .cursor,
            origin: "desktop", workspace: session.cwd, lastActivity: session.lastActivity)
        var namedSession = session
        namedSession.sessionName = "Desktop native name"
        XCTAssertEqual(store.title(for: cli, observedSession: namedSession), .unavailable)
        XCTAssertEqual(store.title(for: desktop, observedSession: namedSession), .native("Desktop native name"))
        await store.refresh(records: [cursor], observedSessions: [])
        let reads = await reader.count
        XCTAssertEqual(reads, 0)
    }

    private func fixture(_ id: String) -> SessionState {
        var info = SessionClientInfo.default(for: .codex)
        info.bundleIdentifier = "com.openai.codex"
        info.origin = "desktop"
        return SessionState(
            sessionId: MacIslandProductPolicy.observedSessionKey(nativeSessionID: id, clientInfo: info),
            cwd: "/tmp/sample-workspace", projectName: "sample-workspace", provider: .codex,
            clientInfo: info, ingress: .codexAppServer)
    }
}

private actor TitleResponses {
    private var value: String?
    private(set) var count = 0
    func set(_ value: String?) { self.value = value }
    func read(_ record: RecentSessionRecord) throws -> String? {
        count += 1
        guard let value else { throw URLError(.cannotConnectToHost) }
        return value
    }
}

private actor DelayedTitleReader {
    private let onStart: @Sendable () -> Void
    private var pending: [String: CheckedContinuation<String?, Error>] = [:]
    init(onStart: @escaping @Sendable () -> Void) { self.onStart = onStart }
    func read(_ record: RecentSessionRecord) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            pending[record.id] = continuation
            onStart()
        }
    }
    func finish(_ id: String, name: String?) { pending.removeValue(forKey: id)?.resume(returning: name) }
}

private actor BoundedTitleReader {
    let firstFour: XCTestExpectation
    private(set) var started = 0
    private(set) var maximumOutstanding = 0
    private var outstanding = 0
    private var released = false
    private var pending: [CheckedContinuation<Void, Never>] = []
    init(firstFour: XCTestExpectation) { self.firstFour = firstFour }
    func read(_ record: RecentSessionRecord) async -> String? {
        started += 1
        outstanding += 1
        maximumOutstanding = max(maximumOutstanding, outstanding)
        if started == 4 { firstFour.fulfill() }
        if !released { await withCheckedContinuation { pending.append($0) } }
        outstanding -= 1
        return "Native title"
    }
    func release() {
        released = true
        let waiters = pending
        pending.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
