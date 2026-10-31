import AppKit
import Foundation

nonisolated struct ContinuationFileIdentity: Equatable, Sendable {
    let canonicalPath: String
    let device: UInt64
    let inode: UInt64
    let size: UInt64?
    let modifiedAt: Date?

    nonisolated static func read(_ url: URL, tracksContents: Bool) throws -> Self {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        let attributes = try FileManager.default.attributesOfItem(atPath: canonical.path)
        guard let device = attributes[.systemNumber] as? NSNumber,
            let inode = attributes[.systemFileNumber] as? NSNumber
        else {
            throw SessionContinuationError.targetChanged
        }
        return Self(
            canonicalPath: canonical.path, device: device.uint64Value, inode: inode.uint64Value,
            size: tracksContents ? (attributes[.size] as? NSNumber)?.uint64Value : nil,
            modifiedAt: tracksContents ? attributes[.modificationDate] as? Date : nil)
    }
}

nonisolated struct ContinuationWorkspaceIdentity: Equatable, Sendable {
    let directory: ContinuationFileIdentity
    let gitDirectory: ContinuationFileIdentity?
    let gitMarker: ContinuationFileIdentity?
    let gitHead: ContinuationFileIdentity?
    let gitCommonDirectory: ContinuationFileIdentity?
    let gitCommonMarker: ContinuationFileIdentity?
    let gitBacklink: ContinuationFileIdentity?

    nonisolated static func inspect(_ path: String) throws -> Self {
        guard SessionContinuationCommand.isSafeAbsolutePath(path) else {
            throw SessionContinuationError.missingDirectory
        }
        let manager = FileManager.default
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
            manager.isReadableFile(atPath: url.path)
        else {
            throw SessionContinuationError.missingDirectory
        }
        let directory = try ContinuationFileIdentity.read(url, tracksContents: false)
        var ancestor = url
        while ancestor.path != "/" {
            let marker = ancestor.appendingPathComponent(".git")
            if let attributes = try? manager.attributesOfItem(atPath: marker.path) {
                let gitURL: URL
                switch attributes[.type] as? FileAttributeType {
                case .typeDirectory:
                    gitURL = marker
                case .typeRegular:
                    // Linked worktrees have a small gitdir pointer, not a .git directory.
                    guard ((attributes[.size] as? NSNumber)?.intValue ?? 4097) <= 4096,
                        let text = try? String(contentsOf: marker, encoding: .utf8),
                        text.hasPrefix("gitdir: ")
                    else {
                        throw SessionContinuationError.brokenWorktree
                    }
                    let reference = text.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !reference.isEmpty,
                        !reference.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
                    else {
                        throw SessionContinuationError.brokenWorktree
                    }
                    gitURL =
                        reference.hasPrefix("/")
                        ? URL(fileURLWithPath: reference)
                        : ancestor.appendingPathComponent(reference)
                default:
                    throw SessionContinuationError.brokenWorktree
                }
                var gitIsDirectory: ObjCBool = false
                guard manager.fileExists(atPath: gitURL.path, isDirectory: &gitIsDirectory), gitIsDirectory.boolValue,
                    let gitDirectory = try? ContinuationFileIdentity.read(gitURL, tracksContents: false),
                    let head = try? ContinuationFileIdentity.read(
                        gitURL.appendingPathComponent("HEAD"), tracksContents: true)
                else {
                    throw SessionContinuationError.brokenWorktree
                }
                let commonMarker = gitURL.appendingPathComponent("commondir")
                var commonDirectory: ContinuationFileIdentity?
                var commonMarkerIdentity: ContinuationFileIdentity?
                var backlinkIdentity: ContinuationFileIdentity?
                if (try? manager.attributesOfItem(atPath: commonMarker.path)) != nil {
                    let commonReference = try readGitReference(commonMarker)
                    let commonURL = resolveGitReference(commonReference, relativeTo: gitURL)
                    // A linked worktree's HEAD can survive deletion of the main
                    // repository. Its shared objects/refs and return link must
                    // still belong to this worktree before offering continuation.
                    for required in [
                        commonURL, commonURL.appendingPathComponent("objects"),
                        commonURL.appendingPathComponent("refs"),
                    ] {
                        var requiredIsDirectory: ObjCBool = false
                        guard manager.fileExists(atPath: required.path, isDirectory: &requiredIsDirectory),
                            requiredIsDirectory.boolValue, manager.isReadableFile(atPath: required.path)
                        else {
                            throw SessionContinuationError.brokenWorktree
                        }
                    }
                    let backlink = gitURL.appendingPathComponent("gitdir")
                    let backlinkURL = resolveGitReference(try readGitReference(backlink), relativeTo: gitURL)
                    guard
                        backlinkURL.resolvingSymlinksInPath().standardizedFileURL
                            == marker.resolvingSymlinksInPath().standardizedFileURL
                    else {
                        throw SessionContinuationError.brokenWorktree
                    }
                    commonDirectory = try ContinuationFileIdentity.read(commonURL, tracksContents: false)
                    commonMarkerIdentity = try ContinuationFileIdentity.read(commonMarker, tracksContents: true)
                    backlinkIdentity = try ContinuationFileIdentity.read(backlink, tracksContents: true)
                }
                return Self(
                    directory: directory, gitDirectory: gitDirectory,
                    gitMarker: try ContinuationFileIdentity.read(marker, tracksContents: true), gitHead: head,
                    gitCommonDirectory: commonDirectory, gitCommonMarker: commonMarkerIdentity,
                    gitBacklink: backlinkIdentity)
            }
            ancestor.deleteLastPathComponent()
        }
        return Self(
            directory: directory, gitDirectory: nil, gitMarker: nil, gitHead: nil,
            gitCommonDirectory: nil, gitCommonMarker: nil, gitBacklink: nil)
    }

    private nonisolated static func readGitReference(_ url: URL) throws -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            attributes[.type] as? FileAttributeType == .typeRegular,
            ((attributes[.size] as? NSNumber)?.intValue ?? 4097) <= 4096,
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            throw SessionContinuationError.brokenWorktree
        }
        let reference = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty,
            !reference.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            throw SessionContinuationError.brokenWorktree
        }
        return reference
    }

    private nonisolated static func resolveGitReference(_ reference: String, relativeTo directory: URL) -> URL {
        reference.hasPrefix("/") ? URL(fileURLWithPath: reference) : directory.appendingPathComponent(reference)
    }
}

nonisolated struct ContinuationEnvironmentSnapshot: Equatable, Sendable {
    let executablePath: String
    let executableIdentity: ContinuationFileIdentity
    let version: String
    let workspace: ContinuationWorkspaceIdentity
}

@MainActor
protocol SessionContinuationEnvironment {
    func inspect(_ target: SessionContinuationTarget) async throws -> ContinuationEnvironmentSnapshot
}

@MainActor
struct LocalSessionContinuationEnvironment: SessionContinuationEnvironment {
    let executor: any ProcessExecuting
    var searchPath: String = Foundation.ProcessInfo.processInfo.environment["PATH"] ?? ""
    var home: URL = FileManager.default.homeDirectoryForCurrentUser

    init(executor: (any ProcessExecuting)? = nil) {
        self.executor = executor ?? ProcessExecutor.shared
    }

    func inspect(_ target: SessionContinuationTarget) async throws -> ContinuationEnvironmentSnapshot {
        let workspace = try ContinuationWorkspaceIdentity.inspect(target.workingDirectory)
        let executable = try resolveExecutable(target.client)
        let identity = try ContinuationFileIdentity.read(URL(fileURLWithPath: executable), tracksContents: true)
        let versionText = try await probe(executable, arguments: ["--version"])
        guard let version = target.client.validatedVersion(versionText),
            target.client.recognizesHelp(try await probe(executable, arguments: target.client.helpArguments))
        else {
            throw SessionContinuationError.unsupportedVersion
        }
        // The binary or worktree may change while the version/help probes await.
        guard identity == (try ContinuationFileIdentity.read(URL(fileURLWithPath: executable), tracksContents: true)),
            workspace == (try ContinuationWorkspaceIdentity.inspect(target.workingDirectory))
        else {
            throw SessionContinuationError.targetChanged
        }
        return ContinuationEnvironmentSnapshot(
            executablePath: executable, executableIdentity: identity,
            version: version, workspace: workspace)
    }

    private func probe(_ executable: String, arguments: [String]) async throws -> String {
        switch await executor.runWithResult(executable, arguments: arguments, timeout: 5) {
        case .success(let result) where result.isSuccess: return result.output
        default: throw SessionContinuationError.unsupportedVersion
        }
    }

    private func resolveExecutable(_ client: SessionContinuationClient) throws -> String {
        let name = client.executableName
        var candidates = [
            home.appendingPathComponent(".local/bin/\(name)").path,
            home.appendingPathComponent(".\(name)/bin/\(name)").path,
            "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)",
        ]
        if client == .codex,
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
        {
            candidates.append(app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex").path)
            candidates.append(app.appendingPathComponent("Contents/Resources/codex").path)
        }
        candidates += searchPath.split(separator: ":").map { String($0) + "/" + name }
        var foundUnsupported = false
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            guard SessionContinuationCommand.isSafeAbsolutePath(path), !path.contains("/shims/"),
                let values = try? URL(fileURLWithPath: path).resolvingSymlinksInPath()
                    .resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true
            else {
                foundUnsupported = true
                continue
            }
            // Keep the invoked path (some wrappers use argv[0]); separately fingerprint
            // its resolved file so a changed symlink invalidates the preview.
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        throw foundUnsupported ? SessionContinuationError.unsupportedExecutable : .missingExecutable
    }
}

@MainActor
protocol SessionContinuationTerminal {
    /// True is only acceptance of an Apple Event, never verified session restoration.
    func submit(_ command: SessionContinuationCommand) async -> Bool
}

@MainActor
struct TerminalAppSessionContinuation: SessionContinuationTerminal {
    let executor: any ProcessExecuting

    init(executor: (any ProcessExecuting)? = nil) { self.executor = executor ?? ProcessExecutor.shared }

    func submit(_ command: SessionContinuationCommand) async -> Bool {
        switch await executor.runWithResult(
            "/usr/bin/osascript", arguments: ["-e", command.terminalAppleScript], timeout: 10
        ) {
        case .success(let result): return result.isSuccess
        case .failure: return false
        }
    }
}

@MainActor
final class SessionContinuationService {
    static let shared = SessionContinuationService()
    private struct Prepared {
        let preview: SessionContinuationPreview
        let environment: ContinuationEnvironmentSnapshot
        let createdAt: Date
    }
    private let environment: any SessionContinuationEnvironment
    private let terminal: any SessionContinuationTerminal
    private let policy: SessionContinuationExecutionPolicy
    private let currentSession: (String) async -> SessionState?
    private let now: () -> Date
    private var previews: [UUID: Prepared] = [:]
    private var preparing: [String: UUID] = [:]
    private var inFlight: Set<String> = []
    private var requested: [String: Date] = [:]
    private let previewLifetime: TimeInterval = 5 * 60

    init(
        environment: (any SessionContinuationEnvironment)? = nil,
        terminal: (any SessionContinuationTerminal)? = nil,
        policy: SessionContinuationExecutionPolicy = .production,
        currentSession: @escaping (String) async -> SessionState? = SessionContinuationService.lookupSession,
        now: @escaping () -> Date = Date.init
    ) {
        self.environment = environment ?? LocalSessionContinuationEnvironment()
        self.terminal = terminal ?? TerminalAppSessionContinuation()
        self.policy = policy
        self.currentSession = currentSession
        self.now = now
    }

    nonisolated private static func lookupSession(_ id: String) async -> SessionState? {
        await SessionStore.shared.session(for: id)
    }

    func prepare(session: SessionState) async -> Result<SessionContinuationPreview, SessionContinuationError> {
        do {
            let target = try SessionContinuationTarget.make(from: session)
            guard !inFlight.contains(target.sessionKey), requested[target.sessionKey] == nil else {
                throw SessionContinuationError.alreadyRequested
            }
            let generation = UUID()
            preparing[target.sessionKey] = generation
            defer {
                if preparing[target.sessionKey] == generation {
                    preparing.removeValue(forKey: target.sessionKey)
                }
            }
            previews = previews.filter {
                now().timeIntervalSince($0.value.createdAt) < previewLifetime
                    && $0.value.preview.target.sessionKey != target.sessionKey
            }
            let snapshot = try await environment.inspect(target)
            guard preparing[target.sessionKey] == generation, !Task.isCancelled else {
                throw SessionContinuationError.cancelled
            }
            try await validateCurrentTarget(target)
            guard preparing[target.sessionKey] == generation, !Task.isCancelled else {
                throw SessionContinuationError.cancelled
            }
            guard previews.count < 100 else { throw SessionContinuationError.previewExpired }
            let command = SessionContinuationCommand(
                executable: snapshot.executablePath,
                arguments: target.client.arguments(nativeID: target.nativeSessionID),
                workingDirectory: target.workingDirectory)
            let preview = SessionContinuationPreview(
                id: generation, target: target, command: command,
                clientVersion: snapshot.version,
                executionCertified: policy.permits(client: target.client, version: snapshot.version))
            previews[generation] = Prepared(preview: preview, environment: snapshot, createdAt: now())
            preparing.removeValue(forKey: target.sessionKey)
            return .success(preview)
        } catch let error as SessionContinuationError { return .failure(error) } catch {
            return .failure(.targetChanged)
        }
    }

    /// Call only from the explicit confirmation button. The token binds the exact
    /// previously shown command; callers cannot replace its executable or arguments.
    func confirm(previewID: UUID) async -> SessionContinuationResult {
        guard let prepared = previews[previewID],
            now().timeIntervalSince(prepared.createdAt) < previewLifetime
        else {
            previews.removeValue(forKey: previewID)
            return .unavailable(.previewExpired)
        }
        let target = prepared.preview.target
        guard !inFlight.contains(target.sessionKey), requested[target.sessionKey] == nil else {
            return .unavailable(.alreadyRequested)
        }
        guard prepared.preview.executionCertified else { return .unavailable(.notCertified) }
        inFlight.insert(target.sessionKey)
        defer { inFlight.remove(target.sessionKey) }
        do {
            try await validateCurrentTarget(target)
            let latest = try await environment.inspect(target)
            guard latest == prepared.environment else { throw SessionContinuationError.targetChanged }
            guard policy.permits(client: target.client, version: latest.version) else {
                throw SessionContinuationError.notCertified
            }
            try await validateCurrentTarget(target)
            guard previews[previewID] != nil, !Task.isCancelled else { throw SessionContinuationError.cancelled }
            guard now().timeIntervalSince(prepared.createdAt) < previewLifetime else {
                previews.removeValue(forKey: previewID)
                throw SessionContinuationError.previewExpired
            }
            previews.removeValue(forKey: previewID)
            // Mark before awaiting Apple Events. Even an error can mean the command
            // arrived; only a subsequent observed event releases this duplicate guard.
            requested[target.sessionKey] = now()
            let accepted = await terminal.submit(prepared.preview.command)
            return accepted ? .requestSubmitted : .deliveryUncertain
        } catch let error as SessionContinuationError { return .unavailable(error) } catch {
            return .unavailable(.targetChanged)
        }
    }

    func cancel(previewID: UUID) { previews.removeValue(forKey: previewID) }

    func cancelPreparation(sessionKey: String) { preparing.removeValue(forKey: sessionKey) }

    /// A real observation may acknowledge a request; an Apple Event cannot.
    func noteObservedActivity(sessionKey: String, at timestamp: Date) {
        guard let submitted = requested[sessionKey], timestamp > submitted else { return }
        requested.removeValue(forKey: sessionKey)
    }

    private func validateCurrentTarget(_ target: SessionContinuationTarget) async throws {
        if let current = await currentSession(target.sessionKey) {
            guard try SessionContinuationTarget.make(from: current) == target else {
                throw SessionContinuationError.targetChanged
            }
        }
    }
}
