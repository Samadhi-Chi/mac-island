import Darwin
import Foundation
import XCTest

@testable import Ping_Island

final class CodexMonitorLifecycleTests: XCTestCase {
    func testMonitorOnlyNeverAnswersServerApprovalsEvenWithNeverPolicy() async throws {
        let writes = MonitorMetadataRequests()
        let id = "synthetic-no-approval"
        let socket = MonitorTestSocket(
            response: { method in
                method == "thread/list"
                    ? ["data": [["id": id, "approvalMode": "never", "status": ["type": "idle"]]]] : [:]
            }, onRequest: { writes.record($0) })
        let monitor = CodexAppServerMonitor(
            transportFactory: { _ in socket }, suspensionProvider: { false },
            requestTimeout: .seconds(1), allowsOwnedServerLaunch: false)
        await monitor.start()
        for (index, method) in [
            "item/commandExecution/requestApproval", "item/fileChange/requestApproval",
            "item/permissions/requestApproval", "item/tool/requestUserInput",
        ].enumerated() {
            try socket.pushJSON([
                "id": "approval-\(index)", "method": method,
                "params": ["threadId": id, "command": ["echo", "synthetic"], "permissions": [:]],
            ])
        }
        // Ordered metadata read is a barrier after the queued inbound requests.
        _ = try? await monitor.readThreadName(threadId: id)
        await monitor.approve(threadId: id, forSession: true)
        await monitor.deny(threadId: id)
        let answered = await monitor.answer(threadId: id, answers: ["question": ["synthetic"]])
        await monitor.shutdown()
        XCTAssertFalse(answered)
        XCTAssertFalse(writes.values.contains { $0["result"] != nil || $0["error"] != nil })
    }

    func testDefaultTransportUsesOnlyOwnedStdioAndReconnectsAfterClosingIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("synthetic-codex")
        // Exercise a real owned process/pipe without depending on Xcode's
        // Python shim or an interpreter installed on the runner. Only the
        // monitor's numeric request IDs are reflected; no live data is read.
        try #"""
        #!/bin/sh
        [ "$1" = app-server ] && [ "$2" = --listen ] && [ "$3" = stdio:// ] || exit 64
        printf 'started\n' >> "$0.trace"
        while IFS= read -r request; do
            id=$(printf '%s\n' "$request" | /usr/bin/sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([0-9][0-9]*\)".*/\1/p')
            [ -n "$id" ] || continue
            printf '{"id":"%s","result":{"data":[]}}\n' "$id"
            printf 'replied\n' >> "$0.trace"
        done
        """#.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let monitor = CodexAppServerMonitor(
            suspensionProvider: { false }, requestTimeout: .seconds(3),
            executableResolver: { executable.path })
        await monitor.start()
        let first = await monitor.healthSnapshot()
        await monitor.reconnect()
        let reconnected = await monitor.healthSnapshot()
        await monitor.setSuspended(true)
        await monitor.setSuspended(false)
        let resumed = await monitor.healthSnapshot()
        await monitor.shutdown()
        let trace = (try? String(contentsOfFile: executable.path + ".trace", encoding: .utf8)) ?? "not launched"
        XCTAssertEqual(first.phase, .connected, "Initial failure: \(String(describing: first.failure)); \(trace)")
        XCTAssertEqual(
            reconnected.phase, .connected, "Reconnect failure: \(String(describing: reconnected.failure)); \(trace)")
        XCTAssertEqual(resumed.phase, .connected, "Resume failure: \(String(describing: resumed.failure)); \(trace)")
        XCTAssertEqual(trace.components(separatedBy: "started\n").count - 1, 3)
    }

    func testNameReadUsesSummaryOnlyAndDoesNotImportSessionOrLaunchServer() async throws {
        let requests = MonitorMetadataRequests()
        let nativeID = "synthetic-native-title-read"
        let socket = MonitorTestSocket(
            response: { method in
                if method == "thread/read" {
                    return [
                        "thread": ["id": nativeID, "name": "Native  title", "preview": "must not be used as title"]
                    ]
                }
                return method == "thread/list" ? ["data": []] : [:]
            }, onRequest: { requests.record($0) })
        let monitor = CodexAppServerMonitor(
            transportFactory: { _ in socket }, suspensionProvider: { false },
            requestTimeout: .milliseconds(200), allowsOwnedServerLaunch: false
        )
        // A title lookup must not create even a connection before monitoring.
        do {
            _ = try await monitor.readThreadName(threadId: nativeID)
            XCTFail("lookup connected implicitly")
        } catch {}
        XCTAssertTrue(requests.values.isEmpty)
        await monitor.start()
        let name = try await monitor.readThreadName(threadId: nativeID)
        let imported = await SessionStore.shared.session(for: nativeID)
        await monitor.shutdown()
        XCTAssertEqual(name, "Native  title")
        XCTAssertNil(imported)
        let read = try XCTUnwrap(requests.values.first { $0["method"] as? String == "thread/read" })
        let params = try XCTUnwrap(read["params"] as? [String: Any])
        XCTAssertEqual(params["threadId"] as? String, nativeID)
        XCTAssertEqual(params["includeTurns"] as? Bool, false)
        XCTAssertFalse(requests.values.contains { ($0["method"] as? String)?.contains("resume") == true })
    }

    func testNameReadRejectsResponseForDifferentNativeID() async {
        let socket = MonitorTestSocket(response: { method in
            if method == "thread/read" { return ["thread": ["id": "other", "name": "Wrong title"]] }
            return method == "thread/list" ? ["data": []] : [:]
        })
        let monitor = CodexAppServerMonitor(
            transportFactory: { _ in socket }, suspensionProvider: { false },
            requestTimeout: .milliseconds(200), allowsOwnedServerLaunch: false)
        await monitor.start()
        do {
            _ = try await monitor.readThreadName(threadId: "requested")
            XCTFail("wrong thread accepted")
        } catch {}
        await monitor.shutdown()
    }

    func testConcurrentStopsWaitForOwnedChildAndBlockReconnectUntilCleanupFinishes() async throws {
        let cleanupEntered = expectation(description: "owned child cleanup entered")
        let releaseCleanup = MonitorTestLatch()
        let cleanupCalls = MonitorTestCounter()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-monitor-child-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("synthetic-observer")
        let pidFile = directory.appendingPathComponent("observer.pid")
        let script = "#!/bin/sh\ntrap '' TERM\nprintf '%s' \"$$\" > '\(pidFile.path)'\nexec /bin/sleep 30\n"
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        defer { try? FileManager.default.removeItem(at: directory) }
        let factory = MonitorTestSocketFactory { index in
            let socket = MonitorTestSocket()
            if index.isMultiple(of: 2) { socket.fail(URLError(.cannotConnectToHost)) }
            return socket
        }
        let monitor = CodexAppServerMonitor(
            transportFactory: { factory.make($0) }, suspensionProvider: { false },
            requestTimeout: .milliseconds(50), executableResolver: { executable.path },
            ownedProcessStop: { child in
                if await cleanupCalls.next() == 1 {
                    cleanupEntered.fulfill()
                    await releaseCleanup.wait()
                }
                return await CodexOwnedProcessShutdown.stop(child, gracefulTimeout: .milliseconds(50))
            }
        )
        await monitor.start()
        let childReady = await eventually { FileManager.default.fileExists(atPath: pidFile.path) }
        guard let pidText = try? String(contentsOf: pidFile, encoding: .utf8),
            let pid = Int32(pidText)
        else {
            await releaseCleanup.open()
            await monitor.shutdown()
            XCTFail("synthetic owned child did not write its PID")
            return
        }

        let firstStop = Task { await monitor.stop() }
        let secondStop = Task { await monitor.stop() }
        await fulfillment(of: [cleanupEntered], timeout: 3)
        await monitor.start()
        await monitor.reconnect()
        let connectionsDuringStop = factory.count
        await releaseCleanup.open()
        // Even the second caller must not return before the child is gone.
        await secondStop.value
        let childExistsAfterStop = kill(pid, 0) == 0
        // Check restart before awaiting the first caller: cleanup belongs to
        // the shared task, not to whichever caller happens to resume first.
        await monitor.start()
        let restartedHealth = await monitor.healthSnapshot()
        await firstStop.value
        await monitor.shutdown()

        XCTAssertTrue(childReady)
        XCTAssertFalse(childExistsAfterStop)
        XCTAssertEqual(connectionsDuringStop, 2)
        XCTAssertEqual(factory.count, 4)
        XCTAssertEqual(restartedHealth.phase, .connected)
    }

    func testReconnectRecoversAfterTimedOutOwnedChildEventuallyExits() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-monitor-timeout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("synthetic-observer")
        try "#!/bin/sh\nexec /bin/sleep 30\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cleanupCalls = MonitorTestCounter()
        let retainedChild = MonitorTestOwnedChild()
        let factory = MonitorTestSocketFactory { index in
            let socket = MonitorTestSocket()
            if index.isMultiple(of: 2) { socket.fail(URLError(.cannotConnectToHost)) }
            return socket
        }
        let monitor = CodexAppServerMonitor(
            transportFactory: { factory.make($0) }, suspensionProvider: { false },
            requestTimeout: .milliseconds(50), executableResolver: { executable.path },
            ownedProcessStop: { child in
                if await cleanupCalls.next() == 1 {
                    await retainedChild.capture(child)
                    return .timedOut
                }
                return await CodexOwnedProcessShutdown.stop(child)
            }
        )
        await monitor.start()
        await monitor.stop()
        // A timeout does not grant ownership of a replacement child while the
        // original one is still running.
        await monitor.start()
        await monitor.reconnect()
        await monitor.setSuspended(false)
        let connectionsBeforeExit = factory.count
        let childWasRunning = await retainedChild.isRunning
        await retainedChild.finish()

        await monitor.reconnect()
        let health = await monitor.healthSnapshot()
        await monitor.shutdown()

        XCTAssertTrue(childWasRunning)
        XCTAssertEqual(connectionsBeforeExit, 2)
        XCTAssertEqual(factory.count, 4)
        XCTAssertEqual(health.phase, .connected)
    }

    func testShutdownPreventsDelayedStartupAndFutureReconnects() async {
        let suspensionEntered = expectation(description: "startup suspension check entered")
        let releaseSuspension = MonitorTestLatch()
        let factory = MonitorTestSocketFactory { _ in MonitorTestSocket() }
        let monitor = CodexAppServerMonitor(
            transportFactory: { factory.make($0) },
            suspensionProvider: {
                suspensionEntered.fulfill()
                await releaseSuspension.wait()
                return false
            }, allowsOwnedServerLaunch: false
        )
        let startup = Task { await monitor.start() }
        await fulfillment(of: [suspensionEntered], timeout: 3)

        await monitor.shutdown()
        await releaseSuspension.open()
        await startup.value
        await monitor.start()
        await monitor.reconnect()
        await monitor.setSuspended(true)
        await monitor.setSuspended(false)
        await monitor.shutdown()

        XCTAssertEqual(factory.count, 0)
        let health = await monitor.healthSnapshot()
        XCTAssertEqual(health.phase, .stopped)
    }

    func testShutdownInvalidatesRetryEvenWhenItsSleepIgnoresCancellation() async {
        let retryEntered = expectation(description: "retry sleep entered")
        let releaseRetry = MonitorTestLatch()
        let retryReleased = expectation(description: "retry sleep released")
        let factory = MonitorTestSocketFactory { _ in
            MonitorTestSocket { _ in nil }
        }
        let monitor = CodexAppServerMonitor(
            transportFactory: { factory.make($0) }, suspensionProvider: { false },
            retrySleep: { _ in
                retryEntered.fulfill()
                await releaseRetry.wait()
                retryReleased.fulfill()
            }, requestTimeout: .milliseconds(50), allowsOwnedServerLaunch: false
        )
        await monitor.start()
        await fulfillment(of: [retryEntered], timeout: 3)

        await monitor.shutdown()
        await releaseRetry.open()
        await fulfillment(of: [retryReleased], timeout: 3)
        let reopened = await eventually(timeout: .milliseconds(150)) { factory.count > 1 }

        XCTAssertFalse(reopened)
        let health = await monitor.healthSnapshot()
        XCTAssertEqual(health.phase, .stopped)
    }

    func testOrdinaryStopAllowsALaterExplicitRestart() async {
        let factory = MonitorTestSocketFactory { _ in MonitorTestSocket() }
        let monitor = CodexAppServerMonitor(
            transportFactory: { factory.make($0) },
            suspensionProvider: { false }, allowsOwnedServerLaunch: false)
        await monitor.start()
        await monitor.stop()

        await monitor.start()
        let health = await monitor.healthSnapshot()
        await monitor.shutdown()

        XCTAssertEqual(factory.count, 2)
        XCTAssertEqual(health.phase, .connected)
    }

    func testShutdownDuringExecutableResolutionCannotLaunchAChild() async {
        let resolverEntered = expectation(description: "executable resolver entered")
        let releaseResolver = MonitorTestLatch()
        let factory = MonitorTestSocketFactory { _ in
            let socket = MonitorTestSocket()
            socket.fail(URLError(.cannotConnectToHost))
            return socket
        }
        let monitor = CodexAppServerMonitor(
            transportFactory: { factory.make($0) }, suspensionProvider: { false },
            requestTimeout: .milliseconds(50),
            executableResolver: {
                resolverEntered.fulfill()
                await releaseResolver.wait()
                return "/synthetic/codex-fixture"
            }
        )
        let startup = Task { await monitor.start() }
        await fulfillment(of: [resolverEntered], timeout: 3)

        await monitor.shutdown()
        await releaseResolver.open()
        await startup.value

        XCTAssertEqual(factory.count, 1)
        let health = await monitor.healthSnapshot()
        XCTAssertEqual(health.phase, .stopped)
    }

    func testTransportFailureRetriesWhileOldInitialRolloutReadIsStillSuspended() async throws {
        let threadID = "monitor-rollout-\(UUID().uuidString)"
        let readEntered = expectation(description: "initial rollout read entered")
        let releaseRead = MonitorTestLatch()
        let firstSocket = MonitorTestSocket { method in
            guard method == "thread/list" else { return [:] }
            return [
                "data": [
                    [
                        "id": threadID, "cwd": "/tmp/monitor-fixture",
                        "updatedAt": Date().timeIntervalSince1970, "status": ["type": "notLoaded"],
                    ]
                ]
            ]
        }
        let factory = MonitorTestSocketFactory { index in index == 0 ? firstSocket : MonitorTestSocket() }
        let monitor = CodexAppServerMonitor(
            transportFactory: { factory.make($0) }, suspensionProvider: { false },
            retrySleep: { _ in try await Task.sleep(for: .milliseconds(10)) },
            allowsOwnedServerLaunch: false,
            rolloutReader: { _, _, _ in
                readEntered.fulfill()
                // Deliberately ignores cancellation, like an already-running file read.
                await releaseRead.wait()
                return nil
            }
        )
        let initialStart = Task { await monitor.start() }
        await fulfillment(of: [readEntered], timeout: 3)
        firstSocket.fail(URLError(.networkConnectionLost))
        let reconnected = await eventually {
            guard factory.count >= 2 else { return false }
            return (await monitor.healthSnapshot()).phase == .connected
        }
        // Release the old work only after checking that it did not swallow retry.
        await releaseRead.open()
        await initialStart.value
        await monitor.stop()
        await SessionStore.shared.process(.sessionArchived(sessionId: threadID))
        XCTAssertTrue(reconnected)
    }

    func testGuardianNotificationCannotWriteAfterSuspensionDuringSessionLookup() async throws {
        let threadID = "monitor-old-notification-\(UUID().uuidString)"
        let lookupEntered = expectation(description: "session lookup entered")
        let lookupReturned = expectation(description: "session lookup returned")
        let releaseLookup = MonitorTestLatch()
        let socket = MonitorTestSocket()
        let monitor = CodexAppServerMonitor(
            transportFactory: { _ in socket }, suspensionProvider: { false },
            allowsOwnedServerLaunch: false,
            sessionLookup: { id in
                lookupEntered.fulfill()
                await releaseLookup.wait()
                lookupReturned.fulfill()
                return SessionState(
                    sessionId: id, cwd: "/tmp/monitor-fixture", projectName: "Fixture",
                    provider: .codex, clientInfo: SessionClientInfo(kind: .codexCLI), phase: .processing)
            }
        )
        await monitor.start()
        try socket.pushJSON([
            "method": "item/autoApprovalReview/started",
            "params": [
                "threadId": threadID, "targetItemId": "fixture-item", "review": ["status": "inProgress"],
                "action": ["type": "mcpToolCall", "server": "fixture", "toolName": "read"],
            ],
        ])
        await fulfillment(of: [lookupEntered], timeout: 3)
        await monitor.setSuspended(true)
        await releaseLookup.open()
        await fulfillment(of: [lookupReturned], timeout: 3)
        // Give the resumed old receiver a bounded window to make an invalid write.
        let staleWrite = await eventually(timeout: .milliseconds(150)) {
            await SessionStore.shared.session(for: threadID) != nil
        }
        let health = await monitor.healthSnapshot()
        await monitor.stop()
        await SessionStore.shared.process(.sessionArchived(sessionId: threadID))
        XCTAssertFalse(staleWrite)
        XCTAssertEqual(health.phase, .suspended)
    }

    func testReconnectDoesNotCarryClosedTransportApprovalIntoFreshThreadState() async throws {
        let threadID = "monitor-old-request-\(UUID().uuidString)"
        let socket = MonitorTestSocket { method in
            method == "thread/list"
                ? [
                    "data": [
                        [
                            "id": threadID, "cwd": "/tmp/monitor-fixture",
                            "approvalMode": "on-request", "status": ["type": "active"],
                        ]
                    ]
                ] : [:]
        }
        let factory = MonitorTestSocketFactory { index in
            if index == 0 { return socket }
            return MonitorTestSocket { method in
                method == "thread/list"
                    ? [
                        "data": [
                            [
                                "id": threadID, "cwd": "/tmp/monitor-fixture",
                                "approvalMode": "on-request", "status": ["type": "active"],
                            ]
                        ]
                    ] : [:]
            }
        }
        let monitor = CodexAppServerMonitor(
            transportFactory: { factory.make($0) },
            suspensionProvider: { false }, allowsOwnedServerLaunch: false)
        await monitor.start()
        try socket.pushJSON([
            "id": "fixture-approval", "method": "item/commandExecution/requestApproval",
            "params": ["threadId": threadID, "command": ["fixture-read"]],
        ])
        let receivedApproval = await eventually {
            await SessionStore.shared.session(for: threadID)?.intervention?.kind == .approval
        }
        await monitor.reconnect()
        let session = await SessionStore.shared.session(for: threadID)
        await monitor.stop()
        await SessionStore.shared.process(.sessionArchived(sessionId: threadID))
        XCTAssertTrue(receivedApproval)
        XCTAssertNil(session?.intervention)
        XCTAssertEqual(session?.phase, .processing)
    }

    func testRepeatedThreadListTimeoutsKeepBackoffDespiteSuccessfulHandshakes() async {
        let delays = MonitorTestDelays()
        let factory = MonitorTestSocketFactory { _ in
            MonitorTestSocket { method in method == "initialize" ? [:] : nil }
        }
        let monitor = CodexAppServerMonitor(
            transportFactory: { factory.make($0) }, suspensionProvider: { false },
            retrySleep: { delay in
                await delays.append(delay)
                try await Task.sleep(for: .milliseconds(10))
            }, requestTimeout: .milliseconds(200), allowsOwnedServerLaunch: false
        )
        await monitor.start()
        let observedRetries = await eventually { await delays.values.count >= 3 }
        await monitor.stop()
        let recorded = await delays.values
        XCTAssertTrue(observedRetries)
        XCTAssertEqual(Array(recorded.prefix(3)), [1, 2, 4])
        let health = await monitor.healthSnapshot()
        XCTAssertNil(health.lastSuccessfulRead)
    }

    private func eventually(timeout: Duration = .seconds(3), _ predicate: () async -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await predicate()
    }
}

private actor MonitorTestLatch {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private actor MonitorTestDelays {
    private(set) var values: [TimeInterval] = []
    func append(_ value: TimeInterval) { values.append(value) }
}

private actor MonitorTestCounter {
    private var value = 0
    func next() -> Int {
        value += 1
        return value
    }
}

private actor MonitorTestOwnedChild {
    private var child: Process?
    var isRunning: Bool { child?.isRunning == true }
    func capture(_ child: Process) { self.child = child }
    func finish() async {
        if let child { _ = await CodexOwnedProcessShutdown.stop(child) }
    }
}

nonisolated private final class MonitorTestSocketFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var created = 0
    private let build: @Sendable (Int) -> MonitorTestSocket
    init(_ build: @escaping @Sendable (Int) -> MonitorTestSocket) { self.build = build }
    var count: Int { lock.withLock { created } }
    func make(_ url: URL) -> any CodexMonitorTransport {
        let index = lock.withLock {
            let value = created
            created += 1
            return value
        }
        return build(index)
    }
}

nonisolated private final class MonitorTestSocket: CodexMonitorTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [Result<URLSessionWebSocketTask.Message, Error>] = []
    private var receiver: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    private var closed = false
    private let response: @Sendable (String) -> [String: Any]?
    private let onRequest: @Sendable ([String: Any]) -> Void

    init(
        response: @escaping @Sendable (String) -> [String: Any]? = { method in
            method == "thread/list" ? ["data": []] : [:]
        }, onRequest: @escaping @Sendable ([String: Any]) -> Void = { _ in }
    ) {
        self.response = response
        self.onRequest = onRequest
    }

    func resume() {}
    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        guard case .string(let text) = message,
            let json = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return }
        onRequest(json)
        guard let method = json["method"] as? String, let id = json["id"],
            let result = response(method)
        else { return }
        try pushJSON(["id": id, "result": result])
    }
    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await withCheckedThrowingContinuation { continuation in
            let next = lock.withLock { () -> Result<URLSessionWebSocketTask.Message, Error>? in
                if closed { return .failure(CancellationError()) }
                if !messages.isEmpty { return messages.removeFirst() }
                receiver = continuation
                return nil
            }
            if let next { continuation.resume(with: next) }
        }
    }
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let pending = lock.withLock {
            closed = true
            let pending = receiver
            receiver = nil
            messages.removeAll()
            return pending
        }
        pending?.resume(throwing: CancellationError())
    }
    func pushJSON(_ value: [String: Any]) throws {
        push(.success(.data(try JSONSerialization.data(withJSONObject: value))))
    }
    func fail(_ error: Error) { push(.failure(error)) }
    private func push(_ message: Result<URLSessionWebSocketTask.Message, Error>) {
        let pending = lock.withLock { () -> CheckedContinuation<URLSessionWebSocketTask.Message, Error>? in
            guard !closed else { return nil }
            if let pending = receiver {
                receiver = nil
                return pending
            }
            messages.append(message)
            return nil
        }
        pending?.resume(with: message)
    }
}

nonisolated private final class MonitorMetadataRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [[String: Any]] = []
    var values: [[String: Any]] { lock.withLock { stored } }
    func record(_ value: [String: Any]) { lock.withLock { stored.append(value) } }
}
