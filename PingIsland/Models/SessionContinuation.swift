import Foundation

/// Native commands remain a separate, explicitly requested action from read-only monitoring.
nonisolated enum SessionContinuationClient: String, CaseIterable, Hashable, Sendable {
    case codex, claude, openCode, hermes

    nonisolated var executableName: String {
        switch self {
        case .codex: "codex"
        case .claude: "claude"
        case .openCode: "opencode"
        case .hermes: "hermes"
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .codex: "Codex CLI"
        case .claude: "Claude Code CLI"
        case .openCode: "OpenCode CLI"
        case .hermes: "Hermes CLI"
        }
    }

    nonisolated func arguments(nativeID: String) -> [String] {
        switch self {
        case .codex: ["resume", nativeID]
        case .claude, .hermes: ["--resume", nativeID]
        case .openCode: ["--session", nativeID]
        }
    }

    nonisolated var helpArguments: [String] {
        self == .codex ? ["resume", "--help"] : ["--help"]
    }

    nonisolated func acceptsNativeID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 256,
            id.unicodeScalars.allSatisfy({
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains(
                    $0)
            }), id.first != "-"
        else { return false }
        switch self {
        case .codex, .claude:
            // Both CLIs also accept names. Only an observed UUID identifies one session.
            return UUID(uuidString: id) != nil
        case .openCode:
            return id.hasPrefix("ses_") && id.count > 4
        case .hermes:
            // Hermes reserves 'latest' and also accepts titles; neither is an exact ID.
            return id.range(of: #"^\d{8}_\d{6}_(?:[a-fA-F0-9]{6}|[a-fA-F0-9]{8})$"#, options: .regularExpression) != nil
        }
    }

    nonisolated func validatedVersion(_ output: String) -> String? {
        guard let firstLine = output.split(whereSeparator: \.isNewline).first,
            firstLine.count <= 256
        else { return nil }
        let line = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern: String
        switch self {
        case .codex: pattern = #"^codex-cli ([0-9]+\.[0-9]+\.[0-9]+[^\s]*)$"#
        case .claude: pattern = #"^([0-9]+\.[0-9]+\.[0-9]+[^\s]*) \(Claude Code\)$"#
        case .openCode: pattern = #"^([0-9]+\.[0-9]+\.[0-9]+[^\s]*)$"#
        case .hermes: pattern = #"^Hermes Agent v([0-9]+\.[0-9]+\.[0-9]+[^\s]*)(?: .*)?$"#
        }
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let range = Range(match.range(at: 1), in: line)
        else { return nil }
        return String(line[range])
    }

    nonisolated func recognizesHelp(_ output: String) -> Bool {
        switch self {
        case .codex:
            return output.contains("codex resume") && output.contains("[SESSION_ID]")
        case .claude, .hermes:
            return output.contains("--resume")
        case .openCode:
            return output.contains("--session")
        }
    }
}

nonisolated struct SessionContinuationTarget: Equatable, Sendable {
    let sessionKey: String
    let client: SessionContinuationClient
    let nativeSessionID: String
    let workingDirectory: String

    @MainActor static func make(from session: SessionState) throws -> Self {
        guard !session.isRemoteSession else { throw SessionContinuationError.unsupportedSurface }
        let client: SessionContinuationClient
        let origin = session.clientInfo.origin?.lowercased()
        if session.provider == .codex, session.clientInfo.kind == .codexCLI,
            origin == nil || origin == "cli"
        {
            client = .codex
        } else {
            guard session.provider == .claude, origin == "cli" else {
                throw SessionContinuationError.unsupportedSurface
            }
            if session.clientInfo.isOpenCodeClient {
                client = .openCode
            } else if session.clientInfo.isHermesClient {
                client = .hermes
            } else if session.clientInfo.isClaudeCodeClient {
                client = .claude
            } else {
                throw SessionContinuationError.unsupportedSurface
            }
        }
        guard !session.phase.isActive, !session.needsManualAttention,
            session.phase == .ended || (session.pid == nil && session.tty == nil)
        else {
            throw SessionContinuationError.existingSession
        }
        let prefix = MacIslandProductPolicy.observedSessionKey(
            nativeSessionID: "", clientInfo: session.clientInfo
        )
        let nativeID: String
        if !prefix.isEmpty, session.sessionId.hasPrefix(prefix) {
            nativeID = String(session.sessionId.dropFirst(prefix.count))
        } else {
            nativeID = session.sessionId
        }
        guard client.acceptsNativeID(nativeID) else { throw SessionContinuationError.invalidSessionID }
        guard session.cwd != "/", SessionContinuationCommand.isSafeAbsolutePath(session.cwd) else {
            throw SessionContinuationError.missingDirectory
        }
        return Self(
            sessionKey: session.sessionId, client: client, nativeSessionID: nativeID,
            workingDirectory: session.cwd)
    }
}

nonisolated struct SessionContinuationCommand: Equatable, Sendable {
    let executable: String
    let arguments: [String]
    let workingDirectory: String

    nonisolated var shellCommand: String {
        "cd -- \(Self.shellQuote(workingDirectory)) && "
            + ([executable] + arguments).map(Self.shellQuote).joined(separator: " ")
    }

    nonisolated var terminalAppleScript: String {
        // With no `in` target Terminal creates a new window, never injects into an
        // existing session. zsh -f fixes syntax without loading interactive rc files.
        let invocation = "/bin/zsh -f -c \(Self.shellQuote(shellCommand))"
        return """
            tell application id "com.apple.Terminal"
                do script \(Self.appleScriptString(invocation))
                activate
            end tell
            """
    }

    nonisolated static func isSafeAbsolutePath(_ value: String) -> Bool {
        value.hasPrefix("/") && value.utf8.count <= 4096
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func appleScriptString(_ value: String) -> String {
        "\""
            + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

nonisolated enum SessionContinuationError: Error, Equatable, Sendable {
    case unsupportedSurface, existingSession, invalidSessionID, missingDirectory
    case brokenWorktree, missingExecutable, unsupportedExecutable, unsupportedVersion
    case previewExpired, targetChanged, notCertified, alreadyRequested, cancelled

    nonisolated var messageKey: String {
        switch self {
        case .unsupportedSurface: "此会话的来源不支持 CLI 续接。请返回原客户端；桌面和未知来源不会转换为 CLI。"
        case .existingSession: "会话仍有活动或已知终端，请先使用“返回会话”。"
        case .invalidSessionID: "无法确认原生会话 ID，不能生成续接命令。"
        case .missingDirectory: "原工作目录已不存在或无法读取，请在原客户端确认目录。"
        case .brokenWorktree: "工作目录的 Git worktree 已失效，请先修复目录关联。"
        case .missingExecutable: "未找到客户端的绝对可执行路径。"
        case .unsupportedExecutable: "此程序路径无法可靠校验，请使用客户端的直接安装版本。"
        case .unsupportedVersion: "无法确认当前客户端版本或续接参数。"
        case .previewExpired: "预览已失效，请重新打开续接预览。"
        case .targetChanged: "会话、程序或工作目录已改变，请重新预览。"
        case .notCertified: "此客户端版本尚未完成真实续接验收；目前仅提供预览和复制命令。"
        case .alreadyRequested: "此会话已有续接请求，请在 Terminal 中确认，避免重复启动。"
        case .cancelled: "续接已取消。"
        }
    }
}

nonisolated struct SessionContinuationCertification: Hashable, Sendable {
    let client: SessionContinuationClient
    let version: String
}

nonisolated struct SessionContinuationExecutionPolicy: Sendable {
    /// Documentation and --help checks do not certify real session continuation.
    /// Add exact client/version entries only alongside recorded live acceptance.
    nonisolated static let production = Self(certifiedVersions: [])
    let certifiedVersions: Set<SessionContinuationCertification>

    nonisolated func permits(client: SessionContinuationClient, version: String) -> Bool {
        certifiedVersions.contains(.init(client: client, version: version))
    }
}

nonisolated struct SessionContinuationPreview: Identifiable, Equatable, Sendable {
    let id: UUID
    let target: SessionContinuationTarget
    let command: SessionContinuationCommand
    let clientVersion: String
    let executionCertified: Bool
}

nonisolated enum SessionContinuationResult: Equatable, Sendable {
    case requestSubmitted
    /// A timeout/error is not proof that Terminal failed to receive the command.
    case deliveryUncertain
    case unavailable(SessionContinuationError)

    nonisolated var messageKey: String {
        switch self {
        case .requestSubmitted: "续接请求已发送到新的 Terminal 窗口，请在那里确认目标会话。"
        case .deliveryUncertain: "无法确认 Terminal 是否收到请求，请先检查 Terminal，避免重复启动。"
        case .unavailable(let error): error.messageKey
        }
    }
}
