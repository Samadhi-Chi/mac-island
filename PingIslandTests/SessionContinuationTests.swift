import Foundation
import XCTest

@testable import Ping_Island

@MainActor
final class SessionContinuationTests: XCTestCase {
    private let uuid = "01990000-1234-7000-8000-0123456789ab"

    func testArgumentsContainOnlyTheNativeResumeSelectorAndExactID() throws {
        for client in SessionContinuationClient.allCases {
            let target = try SessionContinuationTarget.make(from: session(client))
            let expectedSelector = client == .codex ? "resume" : client == .openCode ? "--session" : "--resume"
            XCTAssertEqual(client.arguments(nativeID: target.nativeSessionID), [expectedSelector, nativeID(client)])
            XCTAssertFalse(target.nativeSessionID.hasPrefix("observed:"))
        }
    }

    func testRejectsAliasesOptionsAndInjectedSessionIDs() {
        for client in SessionContinuationClient.allCases {
            for value in [
                "", "latest", "--last", "a b", "$(touch /tmp/no)", "x\ny", "name", "observed:client:cli:session",
            ] {
                XCTAssertFalse(client.acceptsNativeID(value), "\(client): \(value)")
            }
        }
        XCTAssertFalse(SessionContinuationClient.codex.acceptsNativeID("ses_not-a-codex-id"))
        XCTAssertFalse(SessionContinuationClient.openCode.acceptsNativeID(uuid))
        XCTAssertFalse(SessionContinuationClient.hermes.acceptsNativeID(uuid))
    }

    func testRejectsDesktopUnknownRemoteAndActiveSessions() {
        for client in SessionContinuationClient.allCases {
            for origin in ["desktop", "unknown", "web", "cron"] {
                var value = session(client)
                value.clientInfo.origin = origin
                XCTAssertThrowsError(try SessionContinuationTarget.make(from: value)) {
                    XCTAssertEqual($0 as? SessionContinuationError, .unsupportedSurface)
                }
            }
        }
        var active = session(.codex)
        active.phase = .processing
        XCTAssertThrowsError(try SessionContinuationTarget.make(from: active)) {
            XCTAssertEqual($0 as? SessionContinuationError, .existingSession)
        }
        active.phase = .idle
        active.tty = "ttys999"
        XCTAssertThrowsError(try SessionContinuationTarget.make(from: active))
        var remote = session(.hermes)
        remote.ingress = .remoteBridge
        XCTAssertThrowsError(try SessionContinuationTarget.make(from: remote))
    }

    func testVersionAndHelpContractsAreClientSpecific() {
        let versions: [(SessionContinuationClient, String, String)] = [
            (.codex, "codex-cli 0.156.0\n", "0.156.0"),
            (.claude, "2.1.267 (Claude Code)\n", "2.1.267"),
            (.openCode, "1.18.32\n", "1.18.32"),
            (.hermes, "Hermes Agent v0.21.4 (2026.9.21) · upstream example\nInstall directory: /tmp/fixture", "0.21.4"),
        ]
        for (client, output, expected) in versions {
            XCTAssertEqual(client.validatedVersion(output), expected)
            XCTAssertNil(client.validatedVersion("not a version"))
            XCTAssertFalse(client.recognizesHelp("unknown command"))
            XCTAssertFalse(SessionContinuationExecutionPolicy.production.permits(client: client, version: expected))
        }
        XCTAssertEqual(
            SessionContinuationClient.codex.validatedVersion("codex-cli 0.158.0-alpha.2.1"), "0.158.0-alpha.2.1")
        XCTAssertTrue(
            SessionContinuationClient.codex.recognizesHelp("Usage: codex resume [OPTIONS] [SESSION_ID] [PROMPT]"))
        XCTAssertTrue(SessionContinuationClient.claude.recognizesHelp("-r, --resume <session>"))
        XCTAssertTrue(SessionContinuationClient.openCode.recognizesHelp("-s, --session session id"))
        XCTAssertTrue(SessionContinuationClient.hermes.recognizesHelp("--resume SESSION"))
    }

    func testCommandQuotingRoundTripsPathsAndArgumentsWithoutEvaluation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("continuation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("project ' \" $literal ; space")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("fake cli ' \" $literal")
        try "#!/bin/sh\nprintf '%s\\n' \"$PWD\" \"$@\"\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let payloads = ["resume", "' \" ; $(printf injected) `printf injected` \\ &"]
        let command = SessionContinuationCommand(
            executable: executable.path, arguments: payloads, workingDirectory: directory.path)
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-f", "-c", command.shellCommand]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, payloads.count + 1)
        XCTAssertEqual(
            URL(fileURLWithPath: try XCTUnwrap(lines.first)).resolvingSymlinksInPath().path,
            directory.resolvingSymlinksInPath().path)
        XCTAssertEqual(Array(lines.dropFirst()), payloads)
        XCTAssertEqual(SessionContinuationCommand.appleScriptString("a\\b\"c"), "\"a\\\\b\\\"c\"")
        XCTAssertTrue(command.terminalAppleScript.contains("do script \"/bin/zsh -f -c "))
        XCTAssertFalse(command.terminalAppleScript.contains("in window"))
    }

    func testWorkspaceDetectsMissingDirectoryBrokenWorktreeAndReplacedGitHead() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "continuation-worktree-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try ContinuationWorkspaceIdentity.inspect(root.path))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try ContinuationWorkspaceIdentity.inspect(root.path)
        let marker = root.appendingPathComponent(".git")
        try "gitdir: missing\n".write(to: marker, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ContinuationWorkspaceIdentity.inspect(root.path)) {
            XCTAssertEqual($0 as? SessionContinuationError, .brokenWorktree)
        }
        let gitDirectory = root.appendingPathComponent("metadata")
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        let head = gitDirectory.appendingPathComponent("HEAD")
        try "ref: refs/heads/main\n".write(to: head, atomically: true, encoding: .utf8)
        try "gitdir: metadata\n".write(to: marker, atomically: true, encoding: .utf8)
        let before = try ContinuationWorkspaceIdentity.inspect(root.path)
        try "ref: refs/heads/feature\n".write(to: head, atomically: true, encoding: .utf8)
        XCTAssertNotEqual(try ContinuationWorkspaceIdentity.inspect(root.path), before)
        XCTAssertFalse(SessionContinuationCommand.isSafeAbsolutePath("relative/project"))
        XCTAssertFalse(SessionContinuationCommand.isSafeAbsolutePath("/tmp/project\ncommand"))
    }

    func testPreparationNeverSubmitsAndUncertifiedVersionsCannotExecute() async throws {
        for client in SessionContinuationClient.allCases {
            let environment = FakeContinuationEnvironment()
            let terminal = FakeContinuationTerminal()
            let service = SessionContinuationService(
                environment: environment, terminal: terminal, currentSession: { _ in nil })
            let preview = try await service.prepare(session: session(client)).get()
            XCTAssertFalse(preview.executionCertified)
            XCTAssertEqual(terminal.commands.count, 0)
            let result = await service.confirm(previewID: preview.id)
            XCTAssertEqual(result, .unavailable(.notCertified))
            XCTAssertEqual(terminal.commands.count, 0)
        }
    }

    func testLinkedWorktreeRejectsMissingCommonRepositoryAndMismatchedReturnLink() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("continuation-common-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: root) }
        let workspace = root.appendingPathComponent("workspace")
        let metadata = root.appendingPathComponent("metadata")
        let common = root.appendingPathComponent("common")
        for directory in [
            workspace, metadata, common.appendingPathComponent("objects"), common.appendingPathComponent("refs"),
        ] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let marker = workspace.appendingPathComponent(".git")
        try "gitdir: ../metadata\n".write(to: marker, atomically: true, encoding: .utf8)
        try "ref: refs/heads/fixture\n".write(
            to: metadata.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        let commonMarker = metadata.appendingPathComponent("commondir")
        try "../common\n".write(to: commonMarker, atomically: true, encoding: .utf8)
        let backlink = metadata.appendingPathComponent("gitdir")
        try "../workspace/.git\n".write(to: backlink, atomically: true, encoding: .utf8)
        let before = try ContinuationWorkspaceIdentity.inspect(workspace.path)
        XCTAssertNotNil(before.gitCommonDirectory)
        XCTAssertNotNil(before.gitCommonMarker)
        XCTAssertNotNil(before.gitBacklink)

        // An equivalent pointer rewritten after preview is still a changed association.
        try (common.path + "\n").write(to: commonMarker, atomically: true, encoding: .utf8)
        XCTAssertNotEqual(try ContinuationWorkspaceIdentity.inspect(workspace.path), before)
        try "../another-workspace/.git\n".write(to: backlink, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ContinuationWorkspaceIdentity.inspect(workspace.path)) {
            XCTAssertEqual($0 as? SessionContinuationError, .brokenWorktree)
        }
        try "../workspace/.git\n".write(to: backlink, atomically: true, encoding: .utf8)
        try manager.removeItem(at: common)
        XCTAssertThrowsError(try ContinuationWorkspaceIdentity.inspect(workspace.path)) {
            XCTAssertEqual($0 as? SessionContinuationError, .brokenWorktree)
        }
        XCTAssertTrue(manager.fileExists(atPath: metadata.appendingPathComponent("HEAD").path))
    }

    func testConfirmedCertifiedCommandReportsOnlyRequestSubmitted() async throws {
        let environment = FakeContinuationEnvironment()
        let terminal = FakeContinuationTerminal()
        let service = certifiedService(environment, terminal)
        let preview = try await service.prepare(session: session(.codex)).get()
        XCTAssertTrue(preview.executionCertified)
        XCTAssertEqual(terminal.commands.count, 0)
        let result = await service.confirm(previewID: preview.id)
        XCTAssertEqual(result, .requestSubmitted)
        XCTAssertEqual(terminal.commands, [preview.command])
        XCTAssertEqual(environment.inspections, 2, "Confirmation must repeat executable/version/workspace validation")
        let duplicate = await service.prepare(session: session(.codex))
        XCTAssertEqual(duplicate.failure, .alreadyRequested)
    }

    func testEnvironmentChangeAndCurrentSessionChangeRequireNewPreview() async throws {
        let environment = FakeContinuationEnvironment()
        let terminal = FakeContinuationTerminal()
        let service = certifiedService(environment, terminal)
        let preview = try await service.prepare(session: session(.codex)).get()
        environment.version = "2.0.0"
        let result1 = await service.confirm(previewID: preview.id)
        XCTAssertEqual(result1, .unavailable(.targetChanged))
        XCTAssertTrue(terminal.commands.isEmpty)

        var current = session(.codex)
        let secondService = SessionContinuationService(
            environment: FakeContinuationEnvironment(), terminal: terminal,
            policy: .init(certifiedVersions: [.init(client: .codex, version: "1.0.0")]),
            currentSession: { _ in current })
        let secondPreview = try await secondService.prepare(session: current).get()
        current.cwd = "/tmp/different-worktree"
        let result2 = await secondService.confirm(previewID: secondPreview.id)
        XCTAssertEqual(result2, .unavailable(.targetChanged))
        XCTAssertTrue(terminal.commands.isEmpty)
    }

    func testDuplicateConfirmationWhileAwaitingTerminalSubmitsOnlyOnce() async throws {
        let environment = FakeContinuationEnvironment()
        let terminal = FakeContinuationTerminal()
        terminal.blocks = true
        let service = certifiedService(environment, terminal)
        let preview = try await service.prepare(session: session(.codex)).get()
        let first = Task { await service.confirm(previewID: preview.id) }
        await terminal.waitForSubmission()
        // Preparing again is guarded even after the consumed token has disappeared.
        let result3 = (await service.prepare(session: session(.codex))).failure
        XCTAssertEqual(result3, .alreadyRequested)
        let result4 = await service.confirm(previewID: preview.id)
        XCTAssertEqual(result4, .unavailable(.previewExpired))
        terminal.complete(true)
        let result5 = await first.value
        XCTAssertEqual(result5, .requestSubmitted)
        XCTAssertEqual(terminal.commands.count, 1)
    }

    func testUncertainDeliveryCannotAutomaticallyReplay() async throws {
        let environment = FakeContinuationEnvironment()
        let terminal = FakeContinuationTerminal()
        terminal.accepted = false
        let service = certifiedService(environment, terminal)
        let value = session(.codex)
        let preview = try await service.prepare(session: value).get()
        let result6 = await service.confirm(previewID: preview.id)
        XCTAssertEqual(result6, .deliveryUncertain)
        let result7 = (await service.prepare(session: value)).failure
        XCTAssertEqual(result7, .alreadyRequested)
        service.noteObservedActivity(sessionKey: value.sessionId, at: .distantPast)
        let result8 = (await service.prepare(session: value)).failure
        XCTAssertEqual(result8, .alreadyRequested)
        service.noteObservedActivity(sessionKey: value.sessionId, at: .distantFuture)
        _ = try await service.prepare(session: value).get()
        XCTAssertEqual(terminal.commands.count, 1)
    }

    func testCancelledAndExpiredPreviewsCannotSubmit() async throws {
        let environment = FakeContinuationEnvironment()
        let terminal = FakeContinuationTerminal()
        var clock = Date()
        let service = SessionContinuationService(
            environment: environment, terminal: terminal,
            policy: .init(certifiedVersions: [.init(client: .codex, version: "1.0.0")]),
            currentSession: { _ in nil }, now: { clock })
        let cancelled = try await service.prepare(session: session(.codex)).get()
        service.cancel(previewID: cancelled.id)
        let result9 = await service.confirm(previewID: cancelled.id)
        XCTAssertEqual(result9, .unavailable(.previewExpired))
        let expired = try await service.prepare(session: session(.codex)).get()
        clock = clock.addingTimeInterval(301)
        let result10 = await service.confirm(previewID: expired.id)
        XCTAssertEqual(result10, .unavailable(.previewExpired))
        XCTAssertTrue(terminal.commands.isEmpty)
    }

    func testCancellationDuringRevalidationDoesNotSubmit() async throws {
        let environment = FakeContinuationEnvironment()
        let terminal = FakeContinuationTerminal()
        let service = certifiedService(environment, terminal)
        let preview = try await service.prepare(session: session(.codex)).get()
        environment.blocksNextInspection = true
        let request = Task { await service.confirm(previewID: preview.id) }
        await environment.waitForInspection()
        service.cancel(previewID: preview.id)
        environment.completeInspection()
        let result = await request.value
        XCTAssertEqual(result, .unavailable(.cancelled))
        XCTAssertTrue(terminal.commands.isEmpty)
    }

    func testPreviewExpiringDuringEnvironmentRevalidationCannotSubmit() async throws {
        let environment = FakeContinuationEnvironment()
        let terminal = FakeContinuationTerminal()
        var clock = Date()
        let service = SessionContinuationService(
            environment: environment, terminal: terminal,
            policy: .init(certifiedVersions: [.init(client: .codex, version: "1.0.0")]),
            currentSession: { _ in nil }, now: { clock })
        let preview = try await service.prepare(session: session(.codex)).get()
        environment.blocksNextInspection = true
        let request = Task { await service.confirm(previewID: preview.id) }
        await environment.waitForInspection()
        clock = clock.addingTimeInterval(300)
        environment.completeInspection()
        let result = await request.value
        XCTAssertEqual(result, .unavailable(.previewExpired))
        XCTAssertTrue(terminal.commands.isEmpty)
        // The expired token has been consumed and does not lock a fresh preview.
        _ = try await service.prepare(session: session(.codex)).get()
    }

    func testPreviewExpiringDuringFinalTargetLookupCannotSubmit() async throws {
        let environment = FakeContinuationEnvironment()
        let terminal = FakeContinuationTerminal()
        var clock = Date()
        var lookups = 0
        let service = SessionContinuationService(
            environment: environment, terminal: terminal,
            policy: .init(certifiedVersions: [.init(client: .codex, version: "1.0.0")]),
            currentSession: { _ in
                lookups += 1
                if lookups == 3 { clock = clock.addingTimeInterval(301) }
                return nil
            }, now: { clock })
        let preview = try await service.prepare(session: session(.codex)).get()
        let result = await service.confirm(previewID: preview.id)
        XCTAssertEqual(result, .unavailable(.previewExpired))
        XCTAssertEqual(lookups, 3)
        XCTAssertTrue(terminal.commands.isEmpty)
    }

    func testProbeErrorsLeaveNoExecutablePreview() async {
        let environment = FakeContinuationEnvironment()
        let terminal = FakeContinuationTerminal()
        let service = certifiedService(environment, terminal)
        for error in [
            SessionContinuationError.missingDirectory, .brokenWorktree, .missingExecutable, .unsupportedVersion,
        ] {
            environment.failure = error
            let result11 = (await service.prepare(session: session(.codex))).failure
            XCTAssertEqual(result11, error)
        }
        XCTAssertTrue(terminal.commands.isEmpty)
    }

    private func certifiedService(_ environment: FakeContinuationEnvironment, _ terminal: FakeContinuationTerminal)
        -> SessionContinuationService
    {
        SessionContinuationService(
            environment: environment, terminal: terminal,
            policy: .init(certifiedVersions: [.init(client: .codex, version: "1.0.0")]), currentSession: { _ in nil })
    }

    private func nativeID(_ client: SessionContinuationClient) -> String {
        switch client {
        case .codex, .claude: uuid
        case .openCode: "ses_abc123"
        case .hermes: "20260926_120000_a1b2c3d4"
        }
    }

    private func session(_ client: SessionContinuationClient) -> SessionState {
        let info: SessionClientInfo
        switch client {
        case .codex: info = .codexCLI()
        case .claude: info = SessionClientInfo(kind: .claudeCode, profileID: "claude-code", origin: "cli")
        case .openCode: info = SessionClientInfo(kind: .custom, profileID: "opencode", origin: "cli")
        case .hermes: info = SessionClientInfo(kind: .custom, profileID: "hermes", origin: "cli")
        }
        return SessionState(
            sessionId: MacIslandProductPolicy.observedSessionKey(nativeSessionID: nativeID(client), clientInfo: info),
            cwd: "/tmp/synthetic-project", projectName: "Fixture", provider: client == .codex ? .codex : .claude,
            clientInfo: info, phase: .ended)
    }
}

@MainActor
private final class FakeContinuationEnvironment: SessionContinuationEnvironment {
    var version = "1.0.0"
    var failure: SessionContinuationError?
    var inspections = 0
    var blocksNextInspection = false
    private var pending: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func waitForInspection() async {
        if pending != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func completeInspection() {
        pending?.resume()
        pending = nil
    }
    func inspect(_ target: SessionContinuationTarget) async throws -> ContinuationEnvironmentSnapshot {
        inspections += 1
        if blocksNextInspection {
            blocksNextInspection = false
            await withCheckedContinuation { continuation in
                pending = continuation
                observer?.resume()
                observer = nil
            }
        }
        if let failure { throw failure }
        let file = ContinuationFileIdentity(
            canonicalPath: "/tmp/fake-client", device: 1, inode: 2, size: 3, modifiedAt: .distantPast)
        let directory = ContinuationFileIdentity(
            canonicalPath: target.workingDirectory, device: 1, inode: 4, size: nil, modifiedAt: nil)
        return ContinuationEnvironmentSnapshot(
            executablePath: file.canonicalPath, executableIdentity: file,
            version: version,
            workspace: .init(
                directory: directory, gitDirectory: nil, gitMarker: nil, gitHead: nil,
                gitCommonDirectory: nil, gitCommonMarker: nil, gitBacklink: nil))
    }
}

@MainActor
private final class FakeContinuationTerminal: SessionContinuationTerminal {
    var commands: [SessionContinuationCommand] = []
    var accepted = true
    var blocks = false
    private var pending: CheckedContinuation<Bool, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func submit(_ command: SessionContinuationCommand) async -> Bool {
        commands.append(command)
        guard blocks else { return accepted }
        return await withCheckedContinuation { continuation in
            pending = continuation
            observer?.resume()
            observer = nil
        }
    }
    func waitForSubmission() async {
        if pending != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func complete(_ result: Bool) {
        pending?.resume(returning: result)
        pending = nil
    }
}

extension Result where Failure == SessionContinuationError {
    fileprivate var failure: SessionContinuationError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
