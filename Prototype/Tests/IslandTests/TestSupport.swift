import Darwin
import Foundation
import IslandShared
import Testing

@testable import IslandApp

enum TestSupportError: Error, CustomStringConvertible {
    case timedOut(String)
    case executableNotFound(String)
    case failedToStartProcess(String)

    var description: String {
        switch self {
        case .timedOut(let message):
            return "Timed out: \(message)"
        case .executableNotFound(let name):
            return "Test executable not found: \(name)"
        case .failedToStartProcess(let message):
            return "Failed to start process: \(message)"
        }
    }
}

@MainActor
final class SnapshotRecorder {
    var snapshot = SessionSnapshot()

    var sessions: [AgentSession] {
        snapshot.sessions
    }
}

func withRunningSocketServer<T>(
    socketPath: String,
    sessionStore: SessionStore,
    approvalCoordinator: ApprovalCoordinator,
    _ body: (SocketServer) async throws -> T
) async throws -> T {
    let server = SocketServer(
        socketPath: socketPath,
        sessionStore: sessionStore,
        approvalCoordinator: approvalCoordinator
    )

    try await server.start()
    do {
        let result = try await body(server)
        await server.stop()
        return result
    } catch {
        await server.stop()
        throw error
    }
}

func withTemporaryDirectory<T>(
    _ body: (URL) async throws -> T
) async throws -> T {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    return try await body(root)
}

func waitUntil(
    timeout: Duration = .seconds(2),
    description: String,
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout

    while clock.now < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(for: .milliseconds(25))
    }

    throw TestSupportError.timedOut(description)
}

enum TestRuntime {
    private static let packageRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    static func executableURL(named name: String) throws -> URL {
        if let configuredDirectory = ProcessInfo.processInfo.environment["MAC_ISLAND_TEST_BIN_DIR"] {
            let executable = URL(fileURLWithPath: configuredDirectory).appendingPathComponent(name)
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw TestSupportError.executableNotFound(name)
            }
            return executable
        }
        let buildRoot = packageRoot.appending(path: ".build", directoryHint: .isDirectory)
        guard
            let enumerator = FileManager.default.enumerator(
                at: buildRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsPackageDescendants]
            )
        else {
            throw TestSupportError.executableNotFound(name)
        }

        var matches: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == name else { continue }
            // Both legacy .build/.../debug and SwiftPM 6.4 out/Products/Debug.
            guard url.path.lowercased().contains("/debug/") else { continue }
            guard FileManager.default.isExecutableFile(atPath: url.path) else { continue }
            matches.append(url)
        }

        if let match = matches.sorted(by: { $0.path.count < $1.path.count }).first {
            return match
        }

        throw TestSupportError.executableNotFound(name)
    }
}

struct ProcessResult {
    let terminationStatus: Int32
    let stdout: String
    let stderr: String
}

final class RunningProcess {
    private let isolatedHome: URL
    private let process: Process
    private let exitState = ProcessExitState()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdinPipe = Pipe()

    init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:],
        stdin: String = "",
        closeStdinOnLaunch: Bool = true
    ) throws {
        isolatedHome = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(
            at: isolatedHome, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        var mergedEnvironment = [
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
            "HOME": isolatedHome.path, "TMPDIR": isolatedHome.path,
        ]
        for (key, value) in environment {
            mergedEnvironment[key] = value
        }
        let home = mergedEnvironment["HOME"] ?? isolatedHome.path
        mergedEnvironment["CFFIXED_USER_HOME"] = home
        mergedEnvironment["CODEX_HOME"] = home + "/.codex"
        mergedEnvironment["XDG_CACHE_HOME"] = home + "/.cache"
        let socket =
            environment["MAC_ISLAND_SOCKET_PATH"] ?? environment["ISLAND_SOCKET_PATH"]
            ?? (isolatedHome.path + "/unused.sock")
        mergedEnvironment["MAC_ISLAND_SOCKET_PATH"] = socket
        mergedEnvironment["ISLAND_SOCKET_PATH"] = socket
        mergedEnvironment[BridgeRuntimeConfig.configPathEnvironmentKey] =
            environment[BridgeRuntimeConfig.configPathEnvironmentKey] ?? (home + "/bridge-config.json")
        process.environment = mergedEnvironment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe
        // Install before run(): the child may exit while an async test hops
        // executors. Foundation's run-loop-based waitUntilExit can miss that
        // wakeup on a different thread; latch termination independently.
        process.terminationHandler = { [exitState] process in
            exitState.record(process.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            throw TestSupportError.failedToStartProcess(error.localizedDescription)
        }

        if !stdin.isEmpty {
            stdinPipe.fileHandleForWriting.write(Data(stdin.utf8))
        }
        if closeStdinOnLaunch {
            try? stdinPipe.fileHandleForWriting.close()
        }
    }

    deinit {
        if process.isRunning {
            process.terminate()
            if exitState.wait(timeout: 1) == nil, process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
                _ = exitState.wait(timeout: 1)
            }
        }
        try? FileManager.default.removeItem(at: isolatedHome)
    }

    var isRunning: Bool {
        process.isRunning
    }

    func writeToStdin(_ string: String) {
        stdinPipe.fileHandleForWriting.write(Data(string.utf8))
    }

    func closeStdin() {
        try? stdinPipe.fileHandleForWriting.close()
    }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }

    func waitForExit(timeout: TimeInterval = 10) -> ProcessResult {
        var status = exitState.wait(timeout: timeout)
        if status == nil {
            Issue.record("Test child process did not exit within \(timeout) seconds")
            terminate()
            status = exitState.wait(timeout: 1)
            if status == nil, process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
                status = exitState.wait(timeout: 1)
            }
        }
        guard let status else {
            return ProcessResult(terminationStatus: -1, stdout: "", stderr: "Test child termination timed out")
        }
        let stdout =
            String(
                data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        let stderr =
            String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        return ProcessResult(
            terminationStatus: status,
            stdout: stdout,
            stderr: stderr
        )
    }
}

/// The Foundation termination callback and test executor access this latch on
/// different threads. All state is protected by the condition.
private final class ProcessExitState: @unchecked Sendable {
    private let condition = NSCondition()
    private var status: Int32?

    func record(_ status: Int32) {
        condition.lock()
        self.status = status
        condition.broadcast()
        condition.unlock()
    }

    func wait(timeout: TimeInterval) -> Int32? {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while status == nil {
            if !condition.wait(until: deadline) { break }
        }
        return status
    }
}

enum TestSocketClient {
    static func send(envelope: BridgeEnvelope, socketPath: String) throws -> BridgeResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.EIO)
        }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        let utf8 = socketPath.utf8CString.map(UInt8.init(bitPattern:))
        guard utf8.count <= maxLength else {
            throw POSIXError(.ENAMETOOLONG)
        }

        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: utf8)
        }

        let connectResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw POSIXError(.ECONNREFUSED)
        }

        let data = try BridgeCodec.encodeEnvelope(envelope)
        try writeAll(data, to: fd)
        shutdown(fd, Int32(SHUT_WR))

        let responseData = try readAll(from: fd)
        if responseData.isEmpty {
            return BridgeResponse(requestID: envelope.id)
        }
        return try BridgeCodec.decodeResponse(responseData)
    }

    private static func writeAll(_ data: Data, to fd: Int32) throws {
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { buffer in
                write(fd, buffer.baseAddress?.advanced(by: offset), data.count - offset)
            }
            guard written >= 0 else {
                throw POSIXError(.EIO)
            }
            offset += written
        }
    }

    private static func readAll(from fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let readCount = read(fd, &buffer, buffer.count)
            if readCount < 0 {
                throw POSIXError(.EIO)
            }
            if readCount == 0 {
                break
            }
            data.append(buffer, count: readCount)
        }

        return data
    }
}
