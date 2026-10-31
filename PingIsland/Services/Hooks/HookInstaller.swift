//
//  HookInstaller.swift
//  PingIsland
//
//  Installs and manages hook integrations for supported clients.
//

import AppKit
import Foundation

nonisolated private enum HookConfigParser {
    static func parseJSONObject(from data: Data) -> [String: Any]? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }

        guard let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        let sanitized = removeTrailingCommas(from: stripJSONComments(from: string))
        guard let sanitizedData = sanitized.data(using: .utf8) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: sanitizedData) as? [String: Any]
    }

    private static func stripJSONComments(from string: String) -> String {
        var output = ""
        var index = string.startIndex
        var isInsideString = false
        var isEscaping = false
        var isLineComment = false
        var isBlockComment = false

        while index < string.endIndex {
            let character = string[index]
            let nextIndex = string.index(after: index)
            let nextCharacter = nextIndex < string.endIndex ? string[nextIndex] : nil

            if isLineComment {
                if character == "\n" {
                    isLineComment = false
                    output.append(character)
                }
                index = nextIndex
                continue
            }

            if isBlockComment {
                if character == "\n" {
                    output.append(character)
                } else if character == "*", nextCharacter == "/" {
                    isBlockComment = false
                    index = string.index(after: nextIndex)
                    continue
                }
                index = nextIndex
                continue
            }

            if isInsideString {
                output.append(character)
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    isInsideString = false
                }
                index = nextIndex
                continue
            }

            if character == "\"" {
                isInsideString = true
                output.append(character)
                index = nextIndex
                continue
            }

            if character == "/", nextCharacter == "/" {
                isLineComment = true
                index = string.index(after: nextIndex)
                continue
            }

            if character == "/", nextCharacter == "*" {
                isBlockComment = true
                index = string.index(after: nextIndex)
                continue
            }

            output.append(character)
            index = nextIndex
        }

        return output
    }

    private static func removeTrailingCommas(from string: String) -> String {
        let characters = Array(string)
        var output = ""
        var index = 0
        var isInsideString = false
        var isEscaping = false

        while index < characters.count {
            let character = characters[index]

            if isInsideString {
                output.append(character)
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    isInsideString = false
                }
                index += 1
                continue
            }

            if character == "\"" {
                isInsideString = true
                output.append(character)
                index += 1
                continue
            }

            if character == "," {
                var lookahead = index + 1
                while lookahead < characters.count, characters[lookahead].isWhitespace {
                    lookahead += 1
                }

                if lookahead < characters.count, characters[lookahead] == "}" || characters[lookahead] == "]" {
                    index += 1
                    continue
                }
            }

            output.append(character)
            index += 1
        }

        return output
    }
}

struct TOMLHookConfigParser {
    struct TOMLHookEntry: Equatable {
        let event: String
        let command: String
        let matcher: String?
        let timeout: Int?
    }

    enum TOMLSegment: Equatable {
        case text(String)
        case hook(TOMLHookEntry)
    }

    static func parse(_ content: String) -> [TOMLSegment] {
        var segments: [TOMLSegment] = []
        let lines = content.components(separatedBy: .newlines)
        var textBuffer: [String] = []
        var currentHookFields: [String: String] = [:]
        var isInHooksBlock = false

        func flushText() {
            if !textBuffer.isEmpty {
                segments.append(.text(textBuffer.joined(separator: "\n")))
                textBuffer = []
            }
        }

        func flushHook() {
            if let entry = makeEntry(from: currentHookFields) {
                segments.append(.hook(entry))
            }
            currentHookFields = [:]
            isInHooksBlock = false
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[[hooks]]") {
                if isInHooksBlock {
                    flushHook()
                }
                flushText()
                isInHooksBlock = true
                currentHookFields = [:]
                continue
            }

            if isInHooksBlock,
                (trimmed.hasPrefix("[[") && !trimmed.hasPrefix("[[hooks]]"))
                    || (trimmed.hasPrefix("[") && !trimmed.hasPrefix("[["))
            {
                flushHook()
                textBuffer.append(line)
                continue
            }

            if isInHooksBlock {
                if let (key, value) = parseKeyValue(line) {
                    currentHookFields[key] = value
                }
                // Blank lines inside hooks are ignored; they don't terminate the block
            } else {
                textBuffer.append(line)
            }
        }

        if isInHooksBlock {
            flushHook()
        }
        flushText()

        return segments
    }

    static func rebuild(segments: [TOMLSegment], newHooks: [TOMLHookEntry]) -> String {
        var output = ""
        var hasTrailingNewline = false

        for segment in segments {
            switch segment {
            case .text(let text):
                if !output.isEmpty, !hasTrailingNewline {
                    output += "\n"
                }
                output += text
                hasTrailingNewline = text.hasSuffix("\n") || text.isEmpty
            case .hook(let entry):
                if !islandManaged(entry) {
                    if !output.isEmpty, !hasTrailingNewline {
                        output += "\n"
                    }
                    output += renderHook(entry)
                    hasTrailingNewline = true
                }
            }
        }

        for entry in newHooks {
            if !output.isEmpty, !hasTrailingNewline {
                output += "\n"
            }
            output += renderHook(entry)
            hasTrailingNewline = true
        }

        return output
    }

    static func containsManagedHooks(_ content: String) -> Bool {
        parse(content).contains { segment in
            if case .hook(let entry) = segment {
                return islandManaged(entry)
            }
            return false
        }
    }

    static func islandManaged(_ entry: TOMLHookEntry) -> Bool {
        entry.command.contains("mac-island-bridge")
    }

    static func makeEntry(from fields: [String: String]) -> TOMLHookEntry? {
        guard let event = fields["event"] else { return nil }
        let command = fields["command"] ?? ""
        let matcher = fields["matcher"]
        let timeout = fields["timeout"].flatMap(Int.init)
        return TOMLHookEntry(event: event, command: command, matcher: matcher, timeout: timeout)
    }

    static func parseKeyValue(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let eqIndex = trimmed.firstIndex(of: "=") else { return nil }
        let key = trimmed[..<eqIndex].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        var rawValue = trimmed[trimmed.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
        // Strip inline TOML comments (simple heuristic: unquoted #)
        rawValue = stripInlineComment(rawValue)
        let value = stripTOMLQuotes(rawValue)
        return (key, value)
    }

    static func stripInlineComment(_ value: String) -> String {
        var inString = false
        var stringChar: Character? = nil
        for (index, char) in value.enumerated() {
            if inString {
                if char == stringChar {
                    inString = false
                    stringChar = nil
                }
                continue
            }
            if char == "\"" || char == "'" {
                inString = true
                stringChar = char
                continue
            }
            if char == "#" {
                return value[..<value.index(value.startIndex, offsetBy: index)].trimmingCharacters(in: .whitespaces)
            }
        }
        return value
    }

    static func stripTOMLQuotes(_ value: String) -> String {
        var result = value
        if result.hasPrefix("\""), result.hasSuffix("\"") {
            result = String(result.dropFirst().dropLast())
        } else if result.hasPrefix("'"), result.hasSuffix("'") {
            result = String(result.dropFirst().dropLast())
        }
        return result
    }

    static func renderHook(_ entry: TOMLHookEntry) -> String {
        var lines = ["[[hooks]]"]
        lines.append("event = \"\(entry.event)\"")
        lines.append("command = \"\(entry.command.replacingOccurrences(of: "\"", with: "\\\""))\"")
        if let matcher = entry.matcher {
            lines.append("matcher = \"\(matcher.replacingOccurrences(of: "\"", with: "\\\""))\"")
        }
        if let timeout = entry.timeout {
            lines.append("timeout = \(timeout)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

struct HookInstaller {
    struct QoderCLIHookRefreshStatus: Equatable, Sendable {
        let version: String
        let minimumVersion: String
    }

    struct BridgeHealthStatus: Equatable {
        let isHealthy: Bool
        let message: String
    }

    struct IntegrationBackupSummary: Equatable, Sendable {
        let profileID: String
        let createdAt: Date
        let directoryURL: URL
    }

    private struct IntegrationBackupManifest: Codable {
        struct Entry: Codable {
            let originalPath: String
            let archiveName: String
            let existed: Bool
            let wasDirectory: Bool
        }

        let version: Int
        let profileID: String
        let createdAt: Date
        let entries: [Entry]
    }

    private static let preferredTargetsDefaultsKey = "HookInstaller.preferredTargets.v1"
    private static let eventSelectionsDefaultsKey = "HookInstaller.eventSelections.v1"
    private static let qoderMigrationDefaultsKey = "HookInstaller.preferredTargets.qoder-default.v1"
    private static let qoderCNMigrationDefaultsKey = "HookInstaller.preferredTargets.qoder-cn-default.v1"
    private static let qoderWorkMigrationDefaultsKey = "HookInstaller.preferredTargets.qoderwork-default.v1"
    private static let installedVersionDefaultsKey = "HookInstaller.installedVersion.v1"
    private static let firstLaunchDefaultsKey = "HookInstaller.isFirstLaunch.v1"
    private static let versionMetadataDefaultsKey = "HookInstaller.versionMetadata.v1"
    private static let qoderCLIClaudeHooksMinimumVersion = "0.2.5"
    private static let qoderCLIExecutableRelativePath = ".local/bin/qodercli"
    private static let qoderCNCLIExecutableRelativePath = ".local/bin/qoderclicn"
    private nonisolated static let supportDirectoryName = ".mac-island"
    private nonisolated static let bridgeLauncherName = "mac-island-bridge"
    private nonisolated static let bridgeBinaryName = "PingIslandBridge"
    private nonisolated static let legacyBridgeBinaryName = "IslandBridge"
    private nonisolated static let statusLineScriptName = "island-statusline"
    private static let integrationBackupManifestName = "manifest.json"
    #if APP_STORE
        private static let appStoreHookDirectoryBookmarkDefaultsKey = "HookInstaller.appStoreHookDirectoryBookmark.v1"
    #endif

    private struct VersionMetadata: Codable {
        let version: String
        let build: String
        let installedAt: String
        let previousVersion: String

        var dictionaryValue: [String: Any] {
            [
                "version": version,
                "build": build,
                "installedAt": installedAt,
                "previousVersion": previousVersion,
            ]
        }
    }

    private static func decodeValue<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(type, from: data)
    }

    private static func persistValue<T: Encodable>(_ value: T?, defaults: UserDefaults, key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }

        guard let data = try? JSONEncoder().encode(value) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    private static var defaultPreferredTargets: Set<String> {
        Set(
            ClientProfileRegistry.supportedManagedHookProfiles
                .filter { $0.defaultEnabled && canManage($0) }
                .map(\.id)
        )
    }

    /// Install managed hooks for preferred clients on app launch.
    static func installIfNeeded(
        markPresentationOnboardingPending: (() -> Void)? = nil,
        markHookInstallOnboardingPending: (() -> Void)? = nil
    ) {
        // Check if this is first launch and perform auto-integration
        let isFirstLaunch = checkAndMarkFirstLaunch(
            markPresentationOnboardingPending: markPresentationOnboardingPending
        )

        #if APP_STORE
            if isFirstLaunch {
                if let markHookInstallOnboardingPending {
                    markHookInstallOnboardingPending()
                } else {
                    UserDefaults.standard.set(true, forKey: AppSettingsDefaultKeys.hookInstallOnboardingPending)
                }
            }
            updateVersionMetadata()
            return
        #else
            let qoderCLISupportsClaudeHooks = qoderCLIUsesClaudeCompatibleHooks()
            let qoderCNCLIInstalled = qoderCNCLIUsesClaudeCompatibleHooks()
            var preferredTargets = preferredTargets()
            if qoderCLISupportsClaudeHooks,
                let qoderCLIProfile = ClientProfileRegistry.managedHookProfile(id: "qoder-cli-hooks")
            {
                preferredTargets.insert(qoderCLIProfile.id)
                persistPreferredTargets(preferredTargets)
            }
            if qoderCNCLIInstalled,
                let qoderCNCLIProfile = ClientProfileRegistry.managedHookProfile(id: "qoder-cn-cli-hooks")
            {
                preferredTargets.insert(qoderCNCLIProfile.id)
                persistPreferredTargets(preferredTargets)
            }

            installBridgeLauncherIfNeeded()
            removeLegacyTraeHooks()

            if isFirstLaunch {
                // Defer auto-install of default-enabled profiles to the first-run welcome
                // sheet so the user can choose between defaults and a customized selection.
                if let markHookInstallOnboardingPending {
                    markHookInstallOnboardingPending()
                } else {
                    UserDefaults.standard.set(true, forKey: AppSettingsDefaultKeys.hookInstallOnboardingPending)
                }
                updateVersionMetadata()
                return
            }

            for profile in ClientProfileRegistry.supportedManagedHookProfiles {
                let canManageProfile =
                    canManage(profile)
                    || (profile.id == "qoder-cli-hooks" && qoderCLISupportsClaudeHooks)
                    || (profile.id == "qoder-cn-cli-hooks" && qoderCNCLIInstalled)
                if preferredTargets.contains(profile.id) && canManageProfile {
                    install(profile, persistPreference: false, bypassAvailabilityCheck: !canManage(profile))
                } else {
                    uninstall(profile, persistPreference: false)
                }
            }

            // Update version metadata after installation
            updateVersionMetadata()
        #endif
    }

    /// Run the default first-run install for every defaultEnabled profile.
    static func performFirstRunDefaultInstall() {
        let qoderCLISupportsClaudeHooks = qoderCLIUsesClaudeCompatibleHooks()
        let qoderCNCLIInstalled = qoderCNCLIUsesClaudeCompatibleHooks()
        installBridgeLauncherIfNeeded()
        for profile in ClientProfileRegistry.supportedManagedHookProfiles where profile.defaultEnabled {
            let canManageProfile =
                canManage(profile)
                || (profile.id == "qoder-cli-hooks" && qoderCLISupportsClaudeHooks)
                || (profile.id == "qoder-cn-cli-hooks" && qoderCNCLIInstalled)
            guard canManageProfile else { continue }
            install(profile, persistPreference: true, bypassAvailabilityCheck: !canManage(profile))
        }
    }

    #if APP_STORE
        @discardableResult
        static func restoreAppStoreHookDirectoryAuthorizationIfAvailable() -> Bool {
            guard appStoreAuthorizedHookDirectory == nil else {
                return true
            }

            guard let bookmarkData = UserDefaults.standard.data(forKey: appStoreHookDirectoryBookmarkDefaultsKey) else {
                return false
            }

            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                guard
                    url.standardizedFileURL
                        == UserHomeDirectoryResolver
                        .hookConfigurationHomeDirectory
                        .standardizedFileURL
                else {
                    UserDefaults.standard.removeObject(forKey: appStoreHookDirectoryBookmarkDefaultsKey)
                    return false
                }

                activateAppStoreHookDirectory(url)
                if isStale {
                    persistAppStoreHookDirectoryBookmark(url)
                }
                return true
            } catch {
                UserDefaults.standard.removeObject(forKey: appStoreHookDirectoryBookmarkDefaultsKey)
                return false
            }
        }

        @discardableResult
        static func performFirstRunDefaultInstallWithUserAuthorization() -> Bool {
            guard requestAppStoreHookDirectoryAuthorization() else {
                return false
            }
            performFirstRunDefaultInstall()
            return true
        }

        @discardableResult
        static func installWithUserAuthorization(_ profile: ManagedHookClientProfile) -> Bool {
            guard requestAppStoreHookDirectoryAuthorization() else {
                return false
            }
            install(profile)
            return isInstalled(profile)
        }

        @discardableResult
        static func installWithUserAuthorization(
            _ profile: ManagedHookClientProfile,
            selection: HookInstallSelection
        ) -> Bool {
            guard requestAppStoreHookDirectoryAuthorization() else {
                return false
            }
            install(profile, selection: selection)
            return isInstalled(profile)
        }

        @discardableResult
        static func reinstallWithUserAuthorization(_ profile: ManagedHookClientProfile) -> Bool {
            guard requestAppStoreHookDirectoryAuthorization() else {
                return false
            }
            reinstall(profile)
            return isInstalled(profile)
        }

        @discardableResult
        static func reinstallWithUserAuthorization(
            _ profile: ManagedHookClientProfile,
            selection: HookInstallSelection
        ) -> Bool {
            guard requestAppStoreHookDirectoryAuthorization() else {
                return false
            }
            saveSelection(selection, for: profile)
            reinstall(profile)
            return isInstalled(profile)
        }

        static func uninstallWithUserAuthorization(_ profile: ManagedHookClientProfile) -> Bool {
            guard requestAppStoreHookDirectoryAuthorization() else {
                return false
            }
            uninstall(profile)
            return true
        }

        static func uninstallAllWithUserAuthorization() -> Bool {
            guard requestAppStoreHookDirectoryAuthorization() else {
                return false
            }
            uninstall()
            return true
        }

        private static func requestAppStoreHookDirectoryAuthorization() -> Bool {
            if restoreAppStoreHookDirectoryAuthorizationIfAvailable() {
                return true
            }

            let homeDirectory = UserHomeDirectoryResolver.hookConfigurationHomeDirectory
            let panel = NSOpenPanel()
            panel.title = AppLocalization.string("授权 Hooks 配置目录")
            panel.message = AppLocalization.string("Mac App Store 版本需要你手动授权用户主目录，之后才能写入 Claude、Codex 等客户端的 Hooks 配置。")
            panel.prompt = AppLocalization.string("授权并继续")
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = false
            panel.directoryURL = homeDirectory

            guard panel.runModal() == .OK,
                let selectedURL = panel.url
            else {
                return false
            }

            guard selectedURL.standardizedFileURL == homeDirectory.standardizedFileURL else {
                let alert = NSAlert()
                alert.messageText = AppLocalization.string("请选择用户主目录")
                alert.informativeText = AppLocalization.string("为了同时写入 ~/.claude、~/.codex 等多个客户端配置，请授权你的用户主目录。")
                alert.addButton(withTitle: AppLocalization.string("好"))
                alert.runModal()
                return false
            }

            activateAppStoreHookDirectory(selectedURL)
            persistAppStoreHookDirectoryBookmark(selectedURL)
            return true
        }

        private static func activateAppStoreHookDirectory(_ url: URL) {
            let standardizedURL = url.standardizedFileURL
            let didStartAccess = standardizedURL.startAccessingSecurityScopedResource()
            appStoreAuthorizedHookDirectory = standardizedURL
            if didStartAccess,
                !appStoreSecurityScopedHookDirectories.contains(where: {
                    $0.standardizedFileURL == standardizedURL
                })
            {
                appStoreSecurityScopedHookDirectories.append(standardizedURL)
            }
        }

        private static func persistAppStoreHookDirectoryBookmark(_ url: URL) {
            guard
                let bookmarkData = try? url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            else {
                return
            }
            UserDefaults.standard.set(bookmarkData, forKey: appStoreHookDirectoryBookmarkDefaultsKey)
        }

        private static var appStoreAuthorizedHookDirectory: URL?
        private static var appStoreSecurityScopedHookDirectories: [URL] = []
    #endif

    static func defaultEnabledManageableProfiles() -> [ManagedHookClientProfile] {
        let qoderCLISupportsClaudeHooks = qoderCLIUsesClaudeCompatibleHooks()
        let qoderCNCLIInstalled = qoderCNCLIUsesClaudeCompatibleHooks()
        return ClientProfileRegistry.managedHookProfiles.filter { profile in
            guard profile.defaultEnabled else { return false }
            return canManage(profile)
                || (profile.id == "qoder-cli-hooks" && qoderCLISupportsClaudeHooks)
                || (profile.id == "qoder-cn-cli-hooks" && qoderCNCLIInstalled)
        }
    }

    @MainActor
    static func bridgeHealthStatus(supportDirectory: URL? = nil) -> BridgeHealthStatus {
        // A health query must not create or repair any files. Installation and
        // repair remain explicit integration actions.
        let launcherURL = (supportDirectory ?? islandSupportDirectory())
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent(bridgeLauncherName)
        guard FileManager.default.isExecutableFile(atPath: launcherURL.path) else {
            return BridgeHealthStatus(
                isHealthy: false,
                message: AppLocalization.string("Bridge launcher 未安装或不可执行")
            )
        }

        guard preferredBridgeBinaryURL() != nil else {
            return BridgeHealthStatus(
                isHealthy: false,
                message: AppLocalization.string("Mac Island Bridge 二进制缺失")
            )
        }

        guard launcherContainsCurrentRuntimeEnvironment(launcherURL) else {
            return BridgeHealthStatus(
                isHealthy: false,
                message: AppLocalization.string("Bridge launcher 配置已过期，请通过集成安装操作修复")
            )
        }

        let socketPath = BridgeRuntimePaths.socketPath
        guard FileManager.default.fileExists(atPath: socketPath) else {
            return BridgeHealthStatus(
                isHealthy: false,
                message: AppLocalization.string("Bridge 监听尚未启动，请保持 Mac Island 正在运行后重试")
            )
        }

        guard runBridgeLauncherHealthCheck(launcherURL) else {
            return BridgeHealthStatus(
                isHealthy: false,
                message: AppLocalization.string("Bridge launcher 自检失败，请重启 Mac Island 后重新安装 Hooks")
            )
        }

        return BridgeHealthStatus(
            isHealthy: true,
            message: AppLocalization.string("Bridge 链路正常，Hooks 事件可转发到当前 App")
        )
    }

    /// Check if this is the first launch and mark as installed
    static func checkAndMarkFirstLaunch(
        defaults: UserDefaults = .standard,
        markPresentationOnboardingPending: (() -> Void)? = nil
    ) -> Bool {

        // Check if we've already recorded a version
        if defaults.string(forKey: installedVersionDefaultsKey) != nil {
            return false
        }

        // First launch - mark it
        defaults.set(true, forKey: firstLaunchDefaultsKey)
        if let markPresentationOnboardingPending {
            markPresentationOnboardingPending()
        } else {
            defaults.set(true, forKey: AppSettingsDefaultKeys.presentationModeOnboardingPending)
        }
        return true
    }

    /// Update version metadata for tracking updates
    private static func updateVersionMetadata() {
        let defaults = UserDefaults.standard
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        let versionMetadata = VersionMetadata(
            version: currentVersion,
            build: currentBuild,
            installedAt: ISO8601DateFormatter().string(from: Date()),
            previousVersion: defaults.string(forKey: installedVersionDefaultsKey) ?? ""
        )

        defaults.set(currentVersion, forKey: installedVersionDefaultsKey)
        persistValue(versionMetadata, defaults: defaults, key: versionMetadataDefaultsKey)
    }

    /// Get the installed version metadata
    static func getVersionMetadata() -> [String: Any]? {
        let defaults = UserDefaults.standard

        if let metadata = decodeValue(VersionMetadata.self, from: defaults, key: versionMetadataDefaultsKey) {
            return metadata.dictionaryValue
        }

        guard let legacyMetadata = defaults.dictionary(forKey: versionMetadataDefaultsKey) else {
            return nil
        }

        guard let version = legacyMetadata["version"] as? String,
            let build = legacyMetadata["build"] as? String,
            let installedAt = legacyMetadata["installedAt"] as? String,
            let previousVersion = legacyMetadata["previousVersion"] as? String
        else {
            return legacyMetadata
        }

        let metadata = VersionMetadata(
            version: version,
            build: build,
            installedAt: installedAt,
            previousVersion: previousVersion
        )
        persistValue(metadata, defaults: defaults, key: versionMetadataDefaultsKey)
        return metadata.dictionaryValue
    }

    /// Check if this is a fresh install (never installed before)
    static func isFreshInstall() -> Bool {
        return UserDefaults.standard.string(forKey: installedVersionDefaultsKey) == nil
    }

    /// Get the current installed version
    static func getInstalledVersion() -> String? {
        return UserDefaults.standard.string(forKey: installedVersionDefaultsKey)
    }

    static func install(_ profile: ManagedHookClientProfile) {
        guard MacIslandProductPolicy.supportsManagedHookProfile(id: profile.id) else { return }
        _ = createIntegrationBackup(for: profile)
        install(profile, persistPreference: true)
    }

    static func install(_ profile: ManagedHookClientProfile, selection: HookInstallSelection) {
        guard MacIslandProductPolicy.supportsManagedHookProfile(id: profile.id) else { return }
        _ = createIntegrationBackup(for: profile)
        if profile.supportsEventSelection {
            saveSelection(selection, for: profile)
        }
        install(profile, persistPreference: true)
    }

    static func loadSelection(for profile: ManagedHookClientProfile) -> HookInstallSelection {
        guard profile.supportsEventSelection else {
            return HookInstallSelection.defaultSelection(for: profile)
        }
        guard
            let stored = MacIslandRuntimeEnvironment.makeDefaults().dictionary(forKey: eventSelectionsDefaultsKey)
                as? [String: [String]],
            let names = stored[profile.id]
        else {
            return HookInstallSelection.defaultSelection(for: profile)
        }
        let validNames = Set(profile.events.map(\.name))
        let filtered = Set(names).intersection(validNames)
        guard !filtered.isEmpty else {
            return HookInstallSelection.defaultSelection(for: profile)
        }
        return HookInstallSelection(enabledEventNames: filtered)
    }

    static func saveSelection(_ selection: HookInstallSelection, for profile: ManagedHookClientProfile) {
        var stored =
            (MacIslandRuntimeEnvironment.makeDefaults().dictionary(forKey: eventSelectionsDefaultsKey)
                as? [String: [String]]) ?? [:]
        stored[profile.id] = Array(selection.enabledEventNames).sorted()
        MacIslandRuntimeEnvironment.makeDefaults().set(stored, forKey: eventSelectionsDefaultsKey)
    }

    private static func effectiveEvents(for profile: ManagedHookClientProfile) -> [HookInstallEventDescriptor] {
        guard profile.supportsEventSelection else { return profile.events }
        return loadSelection(for: profile).filteredEvents(for: profile)
    }

    static func createTemporarySettingsFile(for profileID: String, supportDirectory: URL? = nil) -> URL? {
        guard supportDirectory != nil || MacIslandRuntimeEnvironment.allowsLiveIO else { return nil }
        guard let profile = ClientProfileRegistry.managedHookProfile(id: profileID) else {
            return nil
        }

        // Generation is pure with respect to client setup. Explicit installation owns helpers.
        let root = supportDirectory ?? islandSupportDirectory()
        let directory = root.appendingPathComponent("tmp/native-runtime-hooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(profile.id)-\(UUID().uuidString).json")
        let command =
            ([
                root.appendingPathComponent("bin/" + bridgeLauncherName).path,
                "--source", profile.bridgeSource,
            ] + profile.bridgeExtraArguments)
            .map(shellQuotedIfNeeded).joined(separator: " ")
        var hooks: [String: Any] = [:]
        for event in effectiveEvents(for: profile) {
            hooks[event.name] = makeHookEntries(command: command, event: event)
        }
        writeJSONObject(["hooks": hooks], to: fileURL)
        return fileURL
    }

    static func removeTemporarySettingsFile(at url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func reinstall(_ profile: ManagedHookClientProfile) {
        guard MacIslandProductPolicy.supportsManagedHookProfile(id: profile.id) else { return }
        _ = createIntegrationBackup(for: profile)
        let hermesWasEnabled =
            profile.id == "hermes-hooks"
            ? isHermesPluginEnabled(named: "mac_island")
            : true
        uninstall(profile, persistPreference: false)
        install(profile, persistPreference: true)
        if profile.id == "hermes-hooks", !hermesWasEnabled {
            setHermesPluginEnabled(false, named: "mac_island")
        }
    }

    static func uninstall(_ profile: ManagedHookClientProfile) {
        guard MacIslandProductPolicy.supportsManagedHookProfile(id: profile.id) else { return }
        _ = createIntegrationBackup(for: profile)
        uninstall(profile, persistPreference: true)
    }

    static func latestIntegrationBackup(for profile: ManagedHookClientProfile) -> IntegrationBackupSummary? {
        latestIntegrationBackup(profileID: profile.id, backupRoot: integrationBackupRoot())
    }

    @discardableResult
    static func rollback(_ profile: ManagedHookClientProfile) -> Bool {
        guard MacIslandProductPolicy.supportsManagedHookProfile(id: profile.id),
            let backup = latestIntegrationBackup(for: profile)
        else {
            return false
        }
        // Preserve the state being replaced so rollback itself remains reversible.
        _ = createIntegrationBackup(for: profile)
        let restored = restoreIntegrationBackup(
            at: backup.directoryURL,
            allowedRoot: FileManager.default.homeDirectoryForCurrentUser
        )
        if restored {
            var targets = preferredTargets()
            if isInstalled(profile) {
                targets.insert(profile.id)
            } else {
                targets.remove(profile.id)
            }
            persistPreferredTargets(targets)
        }
        return restored
    }

    /// Check if any managed hooks are currently installed.
    static func isInstalled() -> Bool {
        ClientProfileRegistry.supportedManagedHookProfiles.contains { isInstalled($0) }
    }

    static func isInstalled(_ profile: ManagedHookClientProfile) -> Bool {
        switch profile.installationKind {
        case .jsonHooks:
            return profile.configurationURLs.contains { containsManagedHooks(at: $0, profile: profile) }
        case .pluginFile:
            return profile.configurationURLs.contains { containsManagedPlugin(at: $0, profile: profile) }
                && isManagedPluginEnabled(profile)
        case .pluginDirectory:
            let containsPlugin = profile.configurationURLs.contains {
                containsManagedPluginDirectory(at: $0, profile: profile)
            }
            return containsPlugin
                && (profile.id != "hermes-hooks" || isHermesPluginEnabled(named: "mac_island"))
                && (profile.id != "dsh-hooks" || isManagedDSHPluginEnabled(profile))
        case .hookDirectory:
            return profile.configurationURLs.contains { containsManagedHookDirectory(at: $0, profile: profile) }
                && isInternalHookEnabled(profile)
        case .tomlHooks:
            return profile.configurationURLs.contains { containsManagedTOMLHooks(at: $0) }
        }
    }

    /// Uninstall hooks for all managed targets.
    static func uninstall() {
        for profile in ClientProfileRegistry.supportedManagedHookProfiles {
            _ = createIntegrationBackup(for: profile)
            uninstall(profile, persistPreference: false)
        }
        persistPreferredTargets(Set<String>())
    }

    private static func install(
        _ profile: ManagedHookClientProfile,
        persistPreference: Bool,
        bypassAvailabilityCheck: Bool = false
    ) {
        if persistPreference {
            var targets = preferredTargets()
            targets.insert(profile.id)
            persistPreferredTargets(targets)
        }

        guard bypassAvailabilityCheck || canManage(profile) else {
            return
        }

        installBridgeLauncherIfNeeded()
        removeLegacyManagedArtifacts(for: profile)
        switch profile.installationKind {
        case .jsonHooks:
            for url in installationTargets(for: profile) {
                updateHooks(at: url, profile: profile)
            }
        case .pluginFile:
            for url in installationTargets(for: profile) {
                writeManagedPlugin(at: url, profile: profile)
            }
            setManagedPluginEnabled(true, for: profile)
        case .pluginDirectory:
            for url in installationTargets(for: profile) {
                writeManagedPluginDirectory(at: url, profile: profile)
            }
            if profile.id == "hermes-hooks" {
                setHermesPluginEnabled(true, named: "mac_island")
            } else if profile.id == "dsh-hooks" {
                setManagedDSHPluginEnabled(true, for: profile)
            }
        case .hookDirectory:
            for url in installationTargets(for: profile) {
                writeManagedHookDirectory(at: url, profile: profile)
            }
            setInternalHookEnabled(true, for: profile)
        case .tomlHooks:
            for url in installationTargets(for: profile) {
                updateTOMLHooks(at: url, profile: profile)
            }
        }

        if profile.id == "qwen-code-hooks" {
            applyQwenAskUserQuestionCompatibilityPatchIfNeeded()
        } else if profile.id == "codebuddy-cli-hooks" {
            applyCodeBuddyCLIAskUserQuestionCompatibilityPatchIfNeeded()
        }
    }

    private static func uninstall(_ profile: ManagedHookClientProfile, persistPreference: Bool) {
        if persistPreference {
            var targets = preferredTargets()
            targets.remove(profile.id)
            persistPreferredTargets(targets)
        }

        if profile.id == "hermes-hooks" {
            setHermesPluginEnabled(false, named: "mac_island")
        } else if profile.id == "dsh-hooks" {
            setManagedDSHPluginEnabled(false, for: profile)
        }

        switch profile.installationKind {
        case .jsonHooks:
            for url in profile.configurationURLs {
                removeManagedHooks(at: url, profile: profile)
            }
        case .pluginFile:
            for url in profile.configurationURLs {
                removeManagedPlugin(at: url, profile: profile)
            }
            setManagedPluginEnabled(false, for: profile)
        case .pluginDirectory:
            for url in profile.configurationURLs {
                removeManagedPluginDirectory(at: url, profile: profile)
            }
        case .hookDirectory:
            for url in profile.configurationURLs {
                removeManagedHookDirectory(at: url, profile: profile)
            }
            setInternalHookEnabled(false, for: profile)
        case .tomlHooks:
            for url in profile.configurationURLs {
                removeManagedTOMLHooks(at: url)
            }
        }
        removeLegacyManagedArtifacts(for: profile)
    }

    private static func canManage(_ profile: ManagedHookClientProfile) -> Bool {
        if profile.id == "qoder-cli-hooks" {
            return qoderCLIUsesClaudeCompatibleHooks()
        }

        if profile.id == "qoder-cn-cli-hooks" {
            return qoderCNCLIUsesClaudeCompatibleHooks()
        }

        return profile.alwaysVisibleInSettings
            || ClientAppLocator.isInstalled(bundleIdentifiers: profile.localAppBundleIdentifiers)
    }

    static func qoderCLIHookRefreshStatus() -> QoderCLIHookRefreshStatus? {
        guard let version = qoderCLIInstalledVersion(),
            qoderCLIClaudeHooksSupported(version: version)
        else {
            return nil
        }

        return QoderCLIHookRefreshStatus(
            version: version,
            minimumVersion: qoderCLIClaudeHooksMinimumVersion
        )
    }

    private static func qoderCLIUsesClaudeCompatibleHooks() -> Bool {
        qoderCLIHookRefreshStatus() != nil
    }

    static func qoderCLIClaudeHooksSupported(version: String) -> Bool {
        compareSemanticVersions(version, qoderCLIClaudeHooksMinimumVersion) != .orderedAscending
    }

    private static func qoderCLIInstalledVersion() -> String? {
        guard let executableURL = qoderCLIExecutableURL(),
            FileManager.default.isExecutableFile(atPath: executableURL.path),
            let output = runProcessOutput(executableURL.path, arguments: ["-v"])
        else {
            return nil
        }

        return qoderCLIVersion(from: output)
    }

    static func qoderCLIExecutableURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        homeDirectory.appendingPathComponent(qoderCLIExecutableRelativePath, isDirectory: false)
    }

    private static func qoderCNCLIUsesClaudeCompatibleHooks() -> Bool {
        guard let executableURL = qoderCNCLIExecutableURL() else { return false }
        return FileManager.default.isExecutableFile(atPath: executableURL.path)
    }

    static func qoderCNCLIExecutableURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        homeDirectory.appendingPathComponent(qoderCNCLIExecutableRelativePath, isDirectory: false)
    }

    private static func runProcessOutput(
        _ executable: String,
        arguments: [String],
        timeout: DispatchTimeInterval = .seconds(2)
    ) -> String? {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { _ in
            finished.signal()
        }

        do {
            try process.run()
            guard finished.wait(timeout: .now() + timeout) == .success else {
                if process.isRunning {
                    process.terminate()
                }
                return nil
            }
            guard process.terminationStatus == 0 else { return nil }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            return [
                String(data: data, encoding: .utf8),
                String(data: errorData, encoding: .utf8),
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
        } catch {
            return nil
        }
    }

    static func qoderCLIVersion(from output: String) -> String? {
        let pattern = #"(?<!\d)(\d+(?:\.\d+){1,3})(?:[-+][0-9A-Za-z.-]+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, range: range),
            let versionRange = Range(match.range(at: 1), in: output)
        else {
            return nil
        }
        return String(output[versionRange])
    }

    static func compareSemanticVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsComponents = numericVersionComponents(lhs)
        let rhsComponents = numericVersionComponents(rhs)
        let count = max(lhsComponents.count, rhsComponents.count)

        for index in 0..<count {
            let lhsValue = index < lhsComponents.count ? lhsComponents[index] : 0
            let rhsValue = index < rhsComponents.count ? rhsComponents[index] : 0
            if lhsValue < rhsValue { return .orderedAscending }
            if lhsValue > rhsValue { return .orderedDescending }
        }

        return .orderedSame
    }

    private static func numericVersionComponents(_ version: String) -> [Int] {
        version.split(separator: ".").map { component in
            let numericPrefix = component.prefix { $0.isNumber }
            return Int(numericPrefix) ?? 0
        }
    }

    private static func preferredTargets() -> Set<String> {
        guard let values = UserDefaults.standard.stringArray(forKey: preferredTargetsDefaultsKey) else {
            return defaultPreferredTargets
        }

        var targets = Set(
            values.compactMap { value in
                ClientProfileRegistry.managedHookProfile(id: value)?.id
            })

        if !UserDefaults.standard.bool(forKey: qoderMigrationDefaultsKey) {
            if let qoderProfile = ClientProfileRegistry.managedHookProfile(id: "qoder-hooks"),
                canManage(qoderProfile)
            {
                targets.insert(qoderProfile.id)
                persistPreferredTargets(targets)
            }
            UserDefaults.standard.set(true, forKey: qoderMigrationDefaultsKey)
        }

        if !UserDefaults.standard.bool(forKey: qoderWorkMigrationDefaultsKey) {
            if let qoderWorkProfile = ClientProfileRegistry.managedHookProfile(id: "qoderwork-hooks"),
                canManage(qoderWorkProfile)
            {
                targets.insert(qoderWorkProfile.id)
                persistPreferredTargets(targets)
            }
            UserDefaults.standard.set(true, forKey: qoderWorkMigrationDefaultsKey)
        }

        if !UserDefaults.standard.bool(forKey: qoderCNMigrationDefaultsKey) {
            if let qoderCNProfile = ClientProfileRegistry.managedHookProfile(id: "qoder-cn-hooks"),
                canManage(qoderCNProfile)
            {
                targets.insert(qoderCNProfile.id)
                persistPreferredTargets(targets)
            }
            UserDefaults.standard.set(true, forKey: qoderCNMigrationDefaultsKey)
        }

        return targets.isEmpty ? [] : targets
    }

    private static func persistPreferredTargets(_ targets: Set<String>) {
        let values = targets.sorted()
        UserDefaults.standard.set(values, forKey: preferredTargetsDefaultsKey)
    }

    private static func installationTargets(for profile: ManagedHookClientProfile) -> [URL] {
        let existingTargets = profile.configurationURLs.filter { url in
            let fileManager = FileManager.default
            return fileManager.fileExists(atPath: url.path)
                || fileManager.fileExists(atPath: url.deletingLastPathComponent().path)
        }

        return existingTargets.isEmpty ? [profile.primaryConfigurationURL] : existingTargets
    }

    private static func integrationBackupRoot() -> URL {
        islandSupportDirectory()
            .appendingPathComponent("backups", isDirectory: true)
            .appendingPathComponent("integrations", isDirectory: true)
    }

    private static func integrationBackupTargets(for profile: ManagedHookClientProfile) -> [URL] {
        var targets = profile.configurationURLs
        targets.append(contentsOf: managedPluginActivationConfigurationURLs(for: profile))
        targets.append(contentsOf: legacyManagedArtifactURLs(for: profile))

        if profile.id == "claude-hooks" {
            targets.append(
                islandSupportDirectory()
                    .appendingPathComponent("bin", isDirectory: true)
                    .appendingPathComponent(statusLineScriptName)
            )
        } else if profile.id == "hermes-hooks" {
            targets.append(
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".hermes/config.yaml")
            )
        }

        var seen = Set<String>()
        return targets.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    @discardableResult
    private static func createIntegrationBackup(
        for profile: ManagedHookClientProfile
    ) -> IntegrationBackupSummary? {
        createIntegrationBackup(
            profileID: profile.id,
            targets: integrationBackupTargets(for: profile),
            backupRoot: integrationBackupRoot()
        )
    }

    @discardableResult
    static func createIntegrationBackup(
        profileID: String,
        targets: [URL],
        backupRoot: URL,
        now: Date = Date()
    ) -> IntegrationBackupSummary? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"

        let operationDirectory =
            backupRoot
            .appendingPathComponent(
                "\(formatter.string(from: now))-\(UUID().uuidString.prefix(8))",
                isDirectory: true
            )
            .appendingPathComponent(profileID, isDirectory: true)
        let itemsDirectory = operationDirectory.appendingPathComponent("items", isDirectory: true)
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)
            var entries: [IntegrationBackupManifest.Entry] = []

            for (index, target) in targets.enumerated() {
                let archiveName = String(format: "%04d", index)
                let archiveURL = itemsDirectory.appendingPathComponent(archiveName)
                var isDirectory: ObjCBool = false
                let existed = fileManager.fileExists(atPath: target.path, isDirectory: &isDirectory)
                if existed {
                    try fileManager.copyItem(at: target, to: archiveURL)
                }
                entries.append(
                    IntegrationBackupManifest.Entry(
                        originalPath: target.standardizedFileURL.path,
                        archiveName: archiveName,
                        existed: existed,
                        wasDirectory: isDirectory.boolValue
                    )
                )
            }

            let manifest = IntegrationBackupManifest(
                version: 1,
                profileID: profileID,
                createdAt: now,
                entries: entries
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            try data.write(
                to: operationDirectory.appendingPathComponent(integrationBackupManifestName),
                options: .atomic
            )
            return IntegrationBackupSummary(
                profileID: profileID,
                createdAt: now,
                directoryURL: operationDirectory
            )
        } catch {
            try? fileManager.removeItem(at: operationDirectory)
            return nil
        }
    }

    static func latestIntegrationBackup(
        profileID: String,
        backupRoot: URL
    ) -> IntegrationBackupSummary? {
        let fileManager = FileManager.default
        guard
            let operationDirectories = try? fileManager.contentsOfDirectory(
                at: backupRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return operationDirectories.compactMap { operationDirectory in
            let profileDirectory = operationDirectory.appendingPathComponent(profileID, isDirectory: true)
            let manifestURL = profileDirectory.appendingPathComponent(integrationBackupManifestName)
            guard let data = try? Data(contentsOf: manifestURL),
                let manifest = try? decoder.decode(IntegrationBackupManifest.self, from: data),
                manifest.version == 1,
                manifest.profileID == profileID
            else {
                return nil
            }
            return IntegrationBackupSummary(
                profileID: profileID,
                createdAt: manifest.createdAt,
                directoryURL: profileDirectory
            )
        }
        .max { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    static func restoreIntegrationBackup(at directoryURL: URL, allowedRoot: URL) -> Bool {
        let manifestURL = directoryURL.appendingPathComponent(integrationBackupManifestName)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: manifestURL),
            let manifest = try? decoder.decode(IntegrationBackupManifest.self, from: data),
            manifest.version == 1
        else {
            return false
        }

        let rootPath = allowedRoot.standardizedFileURL.path
        let validatedEntries: [(IntegrationBackupManifest.Entry, URL, URL)] = manifest.entries.compactMap { entry in
            guard !entry.archiveName.contains("/"), !entry.archiveName.contains("..") else {
                return nil
            }
            let target = URL(fileURLWithPath: entry.originalPath).standardizedFileURL
            let targetPath = target.path
            guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
                return nil
            }
            let archive =
                directoryURL
                .appendingPathComponent("items", isDirectory: true)
                .appendingPathComponent(entry.archiveName)
            if entry.existed, !FileManager.default.fileExists(atPath: archive.path) {
                return nil
            }
            return (entry, target, archive)
        }
        guard validatedEntries.count == manifest.entries.count else { return false }

        let fileManager = FileManager.default
        do {
            for (entry, target, archive) in validatedEntries {
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                guard entry.existed else { continue }

                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let staged = target.deletingLastPathComponent()
                    .appendingPathComponent(".mac-island-restore-\(UUID().uuidString)")
                try fileManager.copyItem(at: archive, to: staged)
                try fileManager.moveItem(at: staged, to: target)
            }
            return true
        } catch {
            return false
        }
    }

    private static func legacyManagedArtifactURLs(for profile: ManagedHookClientProfile) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch profile.id {
        case "opencode-hooks":
            return [
                home.appendingPathComponent(".config/opencode/plugins/ping-island.js"),
                home.appendingPathComponent(".config/opencode/opencode.json"),
                home.appendingPathComponent(".config/opencode/config.json"),
            ]
        case "hermes-hooks":
            return [home.appendingPathComponent(".hermes/plugins/ping_island", isDirectory: true)]
        default:
            return []
        }
    }

    private static func removeLegacyManagedArtifacts(for profile: ManagedHookClientProfile) {
        let fileManager = FileManager.default

        if profile.id == "opencode-hooks" {
            let legacyPluginURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/opencode/plugins/ping-island.js")
            for configURL in legacyManagedArtifactURLs(for: profile).filter({
                $0.pathExtension == "json"
            }) {
                guard let existingData = try? Data(contentsOf: configURL),
                    isManagedPluginEnabled(existingData: existingData, pluginURL: legacyPluginURL)
                else {
                    continue
                }
                let updated = updatedConfigurationData(
                    existingData: existingData,
                    profile: profile,
                    customCommand: "",
                    installing: false,
                    pluginURL: legacyPluginURL
                )
                writeData(updated, to: configURL)
            }
            if legacyManagedArtifact(at: legacyPluginURL, profileID: profile.id) {
                try? fileManager.removeItem(at: legacyPluginURL)
            }
        }

        if profile.id == "hermes-hooks",
            let legacyDirectory = legacyManagedArtifactURLs(for: profile).first,
            legacyManagedDirectory(at: legacyDirectory, profileID: profile.id)
        {
            setHermesPluginEnabled(false, named: "ping_island")
            try? fileManager.removeItem(at: legacyDirectory)
        }
    }

    static func checkIntegration(_ profile: ManagedHookClientProfile) -> Bool {
        guard isInstalled(profile) else { return false }
        if profile.id == "hermes-hooks" {
            return runHermesPluginCommand(["plugins", "doctor", "mac_island", "--ci"])
        }
        if profile.id == "dsh-hooks" {
            return dshInstalledVersion() != nil
        }
        return true
    }

    static func dshInstalledVersion() -> String? {
        guard let executable = dshExecutableURL(),
            let output = runProcessOutput(executable.path, arguments: ["--version"], timeout: .seconds(4))
        else {
            return nil
        }
        let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    private static func dshExecutableURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".npm-global/bin/dsh"),
            home.appendingPathComponent(".local/bin/dsh"),
            URL(fileURLWithPath: "/opt/homebrew/bin/dsh"),
            URL(fileURLWithPath: "/usr/local/bin/dsh"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func isHermesPluginEnabled(named name: String) -> Bool {
        guard
            let output = hermesPluginCommandOutput([
                "plugins", "list", "--plain", "--no-bundled",
            ])
        else {
            return false
        }
        return output.components(separatedBy: .newlines).contains { line in
            let columns = line.split(whereSeparator: \.isWhitespace).map(String.init)
            return columns.count >= 4 && columns[0] == "enabled" && columns[3] == name
        }
    }

    private static func setHermesPluginEnabled(_ enabled: Bool, named name: String) {
        let action = enabled ? "enable" : "disable"
        var arguments = ["plugins", action, name]
        if enabled {
            arguments.append("--no-allow-tool-override")
        }
        _ = runHermesPluginCommand(arguments)
    }

    @discardableResult
    private static func runHermesPluginCommand(_ arguments: [String]) -> Bool {
        hermesPluginCommandOutput(arguments) != nil
    }

    private static func hermesPluginCommandOutput(_ arguments: [String]) -> String? {
        guard let executable = hermesExecutableURL() else { return nil }
        return runProcessOutput(executable.path, arguments: arguments, timeout: .seconds(8))
    }

    private static func hermesExecutableURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/hermes"),
            URL(fileURLWithPath: "/opt/homebrew/bin/hermes"),
            URL(fileURLWithPath: "/usr/local/bin/hermes"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func legacyManagedArtifact(at url: URL, profileID: String) -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return content.contains("Mac Island managed integration: \(profileID)")
            || content.contains("Ping Island managed integration: \(profileID)")
    }

    private static func legacyManagedDirectory(at url: URL, profileID: String) -> Bool {
        ["plugin.yaml", "__init__.py", "plugin.json"].contains { name in
            legacyManagedArtifact(at: url.appendingPathComponent(name), profileID: profileID)
        }
    }

    private static func isInternalHookEnabled(_ profile: ManagedHookClientProfile) -> Bool {
        guard let url = profile.activationConfigurationURL,
            let entryName = profile.activationEntryName,
            let data = try? Data(contentsOf: url)
        else {
            return false
        }
        return isInternalHookEnabled(existingData: data, entryName: entryName)
    }

    private static func isManagedPluginEnabled(_ profile: ManagedHookClientProfile) -> Bool {
        let activationURLs = managedPluginActivationConfigurationURLs(for: profile)
        // OpenCode auto-loads every plugin in ~/.config/opencode/plugins.  A
        // profile without an activation configuration is therefore enabled as
        // soon as its managed plugin file is present.
        guard !activationURLs.isEmpty else {
            return profile.activationConfigurationURL == nil
        }
        return activationURLs.contains { url in
            guard let data = try? Data(contentsOf: url) else {
                return false
            }
            return isManagedPluginEnabled(
                existingData: data,
                pluginURL: profile.primaryConfigurationURL
            )
        }
    }

    private static func setInternalHookEnabled(
        _ enabled: Bool, for profile: ManagedHookClientProfile, customConfigURL: URL? = nil
    ) {
        guard let entryName = profile.activationEntryName else {
            return
        }

        let url = customConfigURL ?? profile.activationConfigurationURL
        guard let url else {
            return
        }

        let existingData = try? Data(contentsOf: url)
        let data = updatedInternalHookConfigurationData(
            existingData: existingData,
            entryName: entryName,
            installing: enabled
        )
        writeData(data, to: url)
    }

    private static func setManagedPluginEnabled(
        _ enabled: Bool,
        for profile: ManagedHookClientProfile,
        customConfigURL: URL? = nil,
        pluginURL: URL? = nil
    ) {
        let pluginURL = pluginURL ?? profile.primaryConfigurationURL
        let urls = managedPluginActivationConfigurationURLs(
            for: profile,
            customConfigURL: customConfigURL
        )
        guard !urls.isEmpty else {
            return
        }

        let targetURLs = enabled ? [urls[0]] : urls
        for url in targetURLs {
            let existingData = try? Data(contentsOf: url)
            let data = updatedConfigurationData(
                existingData: existingData,
                profile: profile,
                customCommand: "",
                installing: enabled,
                pluginURL: pluginURL
            )
            writeData(data, to: url)
        }
    }

    private static func managedPluginActivationConfigurationURLs(
        for profile: ManagedHookClientProfile,
        customConfigURL: URL? = nil
    ) -> [URL] {
        guard let primaryURL = customConfigURL ?? profile.activationConfigurationURL else {
            return []
        }

        guard profile.id == "opencode-hooks" else {
            return [primaryURL]
        }

        // OpenCode 1.14 still reads legacy config.json, but current docs name opencode.json as the global config.
        let legacyURL = primaryURL.deletingLastPathComponent().appendingPathComponent("config.json")
        if legacyURL.standardizedFileURL == primaryURL.standardizedFileURL {
            return [primaryURL]
        }
        return [primaryURL, legacyURL]
    }

    nonisolated private static var dshPatchBeginMarker: String {
        "Mac Island managed integration: dsh-hooks begin"
    }

    nonisolated private static var dshPatchEndMarker: String {
        "Mac Island managed integration: dsh-hooks end"
    }

    private static func isManagedDSHPluginEnabled(_ profile: ManagedHookClientProfile) -> Bool {
        guard profile.id == "dsh-hooks",
            let configURL = profile.activationConfigurationURL,
            let content = try? String(contentsOf: configURL, encoding: .utf8)
        else {
            return false
        }
        return containsManagedDSHPatch(
            content,
            pluginURL: dshPluginEntryURL(for: profile.primaryConfigurationURL)
        )
    }

    private static func setManagedDSHPluginEnabled(
        _ enabled: Bool,
        for profile: ManagedHookClientProfile,
        customConfigURL: URL? = nil,
        pluginURL: URL? = nil
    ) {
        guard profile.id == "dsh-hooks",
            let configURL = customConfigURL ?? profile.activationConfigurationURL
        else {
            return
        }
        if !enabled, !FileManager.default.fileExists(atPath: configURL.path) {
            return
        }
        let current = try? String(contentsOf: configURL, encoding: .utf8)
        let resolvedPluginURL = dshPluginEntryURL(
            for: pluginURL ?? profile.primaryConfigurationURL
        )
        let updated = updatedDSHPatch(
            existing: current,
            pluginURL: resolvedPluginURL,
            installing: enabled
        )
        writeData(Data(updated.utf8), to: configURL)
    }

    nonisolated static func dshPluginEntryURL(for installedURL: URL) -> URL {
        if installedURL.lastPathComponent == "index.mjs" {
            return installedURL
        }
        return installedURL.appendingPathComponent("index.mjs", isDirectory: false)
    }

    nonisolated static func containsManagedDSHPatch(
        _ content: String,
        pluginURL: URL
    ) -> Bool {
        content.contains(dshPatchBeginMarker)
            && content.contains(dshPatchEndMarker)
            && content.contains(pluginURL.absoluteURL.absoluteString)
            && content.contains("id: mac-island-observer")
    }

    nonisolated static func updatedDSHPatch(
        existing: String?,
        pluginURL: URL,
        installing: Bool
    ) -> String {
        var retained: [String] = []
        var insideManagedBlock = false
        for line in (existing ?? "").components(separatedBy: .newlines) {
            if line.contains(dshPatchBeginMarker) {
                insideManagedBlock = true
                continue
            }
            if line.contains(dshPatchEndMarker) {
                insideManagedBlock = false
                continue
            }
            if !insideManagedBlock {
                retained.append(line)
            }
        }

        while retained.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            retained.removeLast()
        }

        if installing {
            retained.removeAll { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "[]" }
            if !retained.isEmpty { retained.append("") }
            let specifier = pluginURL.absoluteURL.absoluteString.replacingOccurrences(of: "'", with: "''")
            retained.append(contentsOf: [
                "# \(dshPatchBeginMarker)",
                "- insert:",
                "    - id: mac-island-observer",
                "      name: '\(specifier)'",
                "# \(dshPatchEndMarker)",
            ])
        } else {
            let hasYAMLValue = retained.contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && !trimmed.hasPrefix("#")
            }
            if !hasYAMLValue {
                if !retained.isEmpty { retained.append("") }
                retained.append("[]")
            }
        }

        return retained.joined(separator: "\n") + "\n"
    }

    private static func removeLegacyTraeHooks() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let legacyPaths = [
            "Library/Application Support/Trae/User/settings.json",
            "Library/Application Support/Trae CN/User/settings.json",
            ".trae/settings.json",
        ]

        for path in legacyPaths {
            let url =
                path
                .split(separator: "/")
                .reduce(home) { partialURL, component in
                    partialURL.appendingPathComponent(String(component))
                }
            removeManagedHooks(at: url)
        }
    }

    private static func removeManagedHooks(at url: URL, profile: ManagedHookClientProfile? = nil) {
        guard let data = try? Data(contentsOf: url),
            var json = HookConfigParser.parseJSONObject(from: data),
            var hooks = json["hooks"] as? [String: Any]
        else {
            return
        }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { entry in
                    isIslandManagedHookEntry(entry, for: profile)
                }

                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        if isManagedStatusLine(json["statusLine"] as? [String: Any]) {
            json.removeValue(forKey: "statusLine")
        }
        writeJSONObject(json, to: url)
    }

    private static func containsManagedTOMLHooks(at url: URL) -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return TOMLHookConfigParser.containsManagedHooks(content)
    }

    private static func updateTOMLHooks(at url: URL, profile: ManagedHookClientProfile) {
        let command = bridgeCommand(source: profile.bridgeSource, extraArguments: profile.bridgeExtraArguments)
        let existingContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let segments = TOMLHookConfigParser.parse(existingContent)
        let newHooks = effectiveEvents(for: profile).map { event -> TOMLHookConfigParser.TOMLHookEntry in
            let matcher =
                event.templates.first.map { template -> String in
                    switch template {
                    case .plain, .direct: return ""
                    case .matcher(let value): return value
                    }
                } ?? ""
            let timeout = event.timeout
            return TOMLHookConfigParser.TOMLHookEntry(
                event: event.name,
                command: command,
                matcher: matcher,
                timeout: timeout
            )
        }
        let updatedContent = TOMLHookConfigParser.rebuild(segments: segments, newHooks: newHooks)
        try? updatedContent.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func removeManagedTOMLHooks(at url: URL) {
        guard let existingContent = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        let segments = TOMLHookConfigParser.parse(existingContent)
        let updatedContent = TOMLHookConfigParser.rebuild(segments: segments, newHooks: [])
        try? updatedContent.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func installBridgeLauncherIfNeeded() {
        let binDirectory = islandSupportDirectory()
            .appendingPathComponent("bin", isDirectory: true)
        let launcherURL = binDirectory.appendingPathComponent(bridgeLauncherName)

        BridgeRuntimePaths.prepareRuntimeDirectory()
        try? FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )

        installBridgeBinaryIfNeeded(in: binDirectory)
        installStatusLineScript(in: binDirectory)

        let bundleBridge =
            (Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent(bridgeBinaryName)
                .path) ?? ""
        let legacyBundleBridge =
            (Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent(legacyBridgeBinaryName)
                .path) ?? ""

        let environmentExports = BridgeRuntimePaths.launcherEnvironment
            .sorted { $0.key < $1.key }
            .map { key, value in
                "export \(key)=\(shellQuoted(value))"
            }
            .joined(separator: "\n")

        let script = """
            #!/bin/zsh
            \(environmentExports)

            SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
            candidates=(
              "$SCRIPT_DIR/\(bridgeBinaryName)"
              "$SCRIPT_DIR/\(legacyBridgeBinaryName)"
              \(shellQuoted(bundleBridge))
              \(shellQuoted(legacyBundleBridge))
            )

            for candidate in "${candidates[@]}"; do
              if [ -n "$candidate" ] && [ -x "$candidate" ]; then
                exec "$candidate" "$@"
              fi
            done

            echo "\(bridgeBinaryName) binary not found" >&2
            exit 127
            """

        if let existingData = try? Data(contentsOf: launcherURL),
            existingData == Data(script.utf8)
        {
            return
        }

        try? Data(script.utf8).write(to: launcherURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: launcherURL.path
        )
    }

    private static func launcherContainsCurrentRuntimeEnvironment(_ launcherURL: URL) -> Bool {
        guard let content = try? String(contentsOf: launcherURL, encoding: .utf8) else {
            return false
        }

        return BridgeRuntimePaths.launcherEnvironment.allSatisfy { key, value in
            content.contains("export \(key)=") && content.contains(shellQuoted(value))
        }
    }

    private static func runBridgeLauncherHealthCheck(_ launcherURL: URL) -> Bool {
        let process = Process()
        process.executableURL = launcherURL
        process.arguments = ["--mode", "health-check"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        do {
            try process.run()
        } catch {
            return false
        }

        guard finished.wait(timeout: .now() + 2) == .success else {
            process.terminate()
            return false
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && output == "ok"
    }

    private static func installStatusLineScript(in binDirectory: URL) {
        let scriptURL = binDirectory.appendingPathComponent(statusLineScriptName)
        let script = """
            #!/bin/bash
            input=$(cat)
            _rl=$(echo "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
            if [ -n "$_rl" ]; then
              _cache_dir="$HOME/.mac-island/run"
              umask 077
              [ ! -L "$HOME/.mac-island" ] && [ ! -L "$_cache_dir" ] || exit 1
              mkdir -p "$_cache_dir" && chmod 700 "$_cache_dir" || exit 1
              _cache_tmp=$(mktemp "$_cache_dir/.claude-rate-limits.XXXXXX") || exit 1
              trap 'rm -f "$_cache_tmp"' EXIT
              printf '%s\\n' "$_rl" > "$_cache_tmp"
              mv -f "$_cache_tmp" "$_cache_dir/claude-rate-limits.json"
            fi
            echo "$input" | jq -r 'if .model.display_name then "[\\(.model.display_name)] \\(.context_window.used_percentage // 0)% context" else empty end' 2>/dev/null
            """

        try? Data(script.utf8).write(to: scriptURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
    }

    private static func installBridgeBinaryIfNeeded(in binDirectory: URL) {
        guard let bundledBridgeURL = preferredBridgeBinaryURL() else {
            return
        }

        let destinationURL = binDirectory.appendingPathComponent(bridgeBinaryName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            let matchesExistingBinary =
                (try? Data(contentsOf: bundledBridgeURL)) == (try? Data(contentsOf: destinationURL))
            if matchesExistingBinary == true {
                return
            }

            try? FileManager.default.removeItem(at: destinationURL)
        }

        try? FileManager.default.copyItem(at: bundledBridgeURL, to: destinationURL)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: destinationURL.path
        )
    }

    private nonisolated static func preferredBridgeBinaryURL() -> URL? {
        guard
            let url = Bundle.main.executableURL?
                .deletingLastPathComponent().appendingPathComponent(bridgeBinaryName),
            FileManager.default.isExecutableFile(atPath: url.path)
        else { return nil }
        return url
    }

    private static func applyQwenAskUserQuestionCompatibilityPatchIfNeeded() {
        guard let cliURL = qwenCLIEntryPointURL(),
            let source = try? String(contentsOf: cliURL, encoding: .utf8),
            let patched = patchedQwenCLISourceIfNeeded(source),
            patched != source
        else {
            return
        }

        try? patched.write(to: cliURL, atomically: true, encoding: .utf8)
    }

    private static func qwenCLIEntryPointURL() -> URL? {
        commandEntryPointURL(named: "qwen")
    }

    static func patchedQwenCLISourceIfNeeded(_ source: String) -> String? {
        let marker = #"const hookAnswerPayload = confirmationDetails.type === "ask_user_question""#
        if source.contains(marker) {
            return source
        }

        let patterns: [(pattern: String, replacement: String)] = [
            (
                #"(\s+if \(hookResult\.updatedInput && typeof reqInfo\.args === "object"\) \{\s+this\.setArgsInternal\(reqInfo\.callId, hookResult\.updatedInput\);\s+\}\s+)await confirmationDetails\.onConfirm\(ToolConfirmationOutcome\.ProceedOnce\);"#,
                """
                $1const hookAnswerPayload = confirmationDetails.type === "ask_user_question" && hookResult.updatedInput && typeof hookResult.updatedInput === "object" && "answers" in hookResult.updatedInput ? { answers: hookResult.updatedInput.answers } : void 0;
                $1await confirmationDetails.onConfirm(ToolConfirmationOutcome.ProceedOnce, hookAnswerPayload);
                """
            ),
            (
                #"(\s+if \(hookResult\.updatedInput\) \{\s+args2 = hookResult\.updatedInput;\s+invocation\.params = hookResult\.updatedInput;\s+\}\s+)await confirmationDetails\.onConfirm\(\s+ToolConfirmationOutcome\.ProceedOnce\s+\);"#,
                """
                $1const hookAnswerPayload = confirmationDetails.type === "ask_user_question" && hookResult.updatedInput && typeof hookResult.updatedInput === "object" && "answers" in hookResult.updatedInput ? { answers: hookResult.updatedInput.answers } : void 0;
                $1await confirmationDetails.onConfirm(
                $1  ToolConfirmationOutcome.ProceedOnce,
                $1  hookAnswerPayload
                $1);
                """
            ),
        ]

        var patched = source
        var didChange = false
        for entry in patterns {
            guard let regex = try? NSRegularExpression(pattern: entry.pattern) else {
                continue
            }
            let range = NSRange(patched.startIndex..., in: patched)
            let updated = regex.stringByReplacingMatches(in: patched, range: range, withTemplate: entry.replacement)
            if updated != patched {
                patched = updated
                didChange = true
            }
        }

        return didChange ? patched : nil
    }

    private static func applyCodeBuddyCLIAskUserQuestionCompatibilityPatchIfNeeded() {
        for cliURL in codeBuddyCLIBundleURLs() {
            guard let source = try? String(contentsOf: cliURL, encoding: .utf8),
                let patched = patchedCodeBuddyCLISourceIfNeeded(source),
                patched != source
            else {
                continue
            }

            try? patched.write(to: cliURL, atomically: true, encoding: .utf8)
        }
    }

    private static func codeBuddyCLIBundleURLs() -> [URL] {
        guard let entryPointURL = commandEntryPointURL(named: "codebuddy") else {
            return []
        }

        let packageURL =
            entryPointURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let distURL = packageURL.appendingPathComponent("dist", isDirectory: true)
        return [
            distURL.appendingPathComponent("codebuddy.js"),
            distURL.appendingPathComponent("codebuddy-headless.js"),
        ].filter { FileManager.default.isWritableFile(atPath: $0.path) }
    }

    private static func commandEntryPointURL(named command: String) -> URL? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", command]
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            guard
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !path.isEmpty
            else {
                return nil
            }
            return URL(fileURLWithPath: path).resolvingSymlinksInPath()
        } catch {
            return nil
        }
    }

    static func patchedCodeBuddyCLISourceIfNeeded(_ source: String) -> String? {
        let marker = "[PingIsland CodeBuddy CLI AskUserQuestion compatibility]"
        if source.contains(marker) {
            return source
        }

        guard let containerAlias = codeBuddyContainerUtilAlias(in: source) else {
            return nil
        }

        var patched = source
        var didChange = false

        let notificationNeedle =
            #"try{await this.hookManager.executeHooks(tV.HookEvent.NOTIFICATION,ec)}catch(ei){this.logger.error("Notification hook execution failed:",ei)}"#
        if patched.contains(notificationNeedle) {
            patched = patched.replacingOccurrences(
                of: notificationNeedle,
                with:
                    #"try{return await this.hookManager.executeHooks(tV.HookEvent.NOTIFICATION,ec)}catch(ei){this.logger.error("Notification hook execution failed:",ei)}"#
            )
            didChange = true
        }

        let permissionNeedle =
            #"let eu=`needs your permission to use ${ea}`;try{await this.sessionHookManager.executeNotificationHooks(ei,eu,tV.NotificationType.PERMISSION_PROMPT)}catch(ei){this.consoleManager.error("Notification hook failed:",ei)}}"#
        if patched.contains(permissionNeedle) {
            let replacement = """
                let eu=`needs your permission to use ${ea}`;try{
                let eI=await this.sessionHookManager.executeNotificationHooks(ei,eu,tV.NotificationType.PERMISSION_PROMPT);
                if("AskUserQuestion"===ea){
                let eR=eI?.hookSpecificOutput?.updatedInput||eI?.hookSpecificOutput?.modifiedInput||eI?.updatedInput||eI?.modifiedInput||eI?.decision?.updatedInput||eI?.hookSpecificOutput?.decision?.updatedInput,eO=eR?.answers;
                if(eO&&"object"==typeof eO){
                let eP=new Map,eD="arguments"in em.rawItem?em.rawItem.arguments:void 0;
                try{let ei="string"==typeof eD?JSON.parse(eD):eD;(Array.isArray(ei?.questions)?ei.questions:[]).forEach((ei,ea)=>{let el="string"==typeof ei?.question?ei.question:"";el&&(eP.set(el,el),"string"==typeof ei?.id&&ei.id&&eP.set(ei.id,el),eP.set(`q_${ea}`,el),eP.set(String(ea),el))})}catch(ei){this.logger.warn?.(`[HandleInterruptions] Failed to parse AskUserQuestion arguments from hook answer: ${ei instanceof Error?ei.message:String(ei)}`)}
                let eN=Object.fromEntries(Object.entries(eO).map(([ei,ea])=>[eP.get(ei)||ei,Array.isArray(ea)?ea.join(", "):ea])),eM=em.rawItem.callId||em.rawItem.id;
                try{\(containerAlias).ContainerUtil.get(el(88056).AskService).doneAsk(eN,eM),this.approve(em),this.logger.info?.(`[PingIsland CodeBuddy CLI AskUserQuestion compatibility] answered id=${eM||"none"}`)}catch(ei){this.logger.warn?.(`[HandleInterruptions] Failed to apply AskUserQuestion hook answer: ${ei instanceof Error?ei.message:String(ei)}`)}
                }}
                }catch(ei){this.consoleManager.error("Notification hook failed:",ei)}}
                """
            patched = patched.replacingOccurrences(of: permissionNeedle, with: replacement)
            didChange = true
        }

        return didChange ? patched : nil
    }

    private static func codeBuddyContainerUtilAlias(in source: String) -> String? {
        guard let permissionRange = source.range(of: #"needs your permission to use"#) else {
            return nil
        }
        let prefix = String(source[..<permissionRange.lowerBound].suffix(200_000))
        guard let regex = try? NSRegularExpression(pattern: #"(?:^|[,\s])([A-Za-z_$][A-Za-z0-9_$]*)=el\(80699\),"#)
        else {
            return nil
        }
        let range = NSRange(prefix.startIndex..., in: prefix)
        guard let match = regex.matches(in: prefix, range: range).last,
            match.numberOfRanges > 1,
            let aliasRange = Range(match.range(at: 1), in: prefix)
        else {
            return nil
        }
        return String(prefix[aliasRange])
    }

    private nonisolated static func normalizedHookEntries(
        _ existingEntries: [[String: Any]]?,
        preferred: [[String: Any]],
        preferredFirst: Bool = false,
        profile: ManagedHookClientProfile? = nil
    ) -> [[String: Any]] {
        let preservedEntries = (existingEntries ?? []).filter { !isIslandManagedHookEntry($0, for: profile) }
        return preferredFirst ? preferred + preservedEntries : preservedEntries + preferred
    }

    private nonisolated static func removingIslandManagedHooks(
        from hooks: [String: Any],
        profile: ManagedHookClientProfile? = nil
    ) -> [String: Any] {
        var updated = hooks
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll { isIslandManagedHookEntry($0, for: profile) }
            if entries.isEmpty {
                updated.removeValue(forKey: event)
            } else {
                updated[event] = entries
            }
        }
        return updated
    }

    private static func updateHooks(at url: URL, profile: ManagedHookClientProfile) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
            let existing = HookConfigParser.parseJSONObject(from: data)
        {
            json = existing
        }

        let activeEvents = effectiveEvents(for: profile)

        if profile.brand == .copilot {
            // GitHub Copilot expects flat command entries and does not include the
            // hook event name in stdin, so we bind the event explicitly here.
            json["version"] = 1
            var hooks = removingIslandManagedHooks(from: json["hooks"] as? [String: Any] ?? [:])
            for event in activeEvents {
                let command = bridgeCommand(
                    source: profile.bridgeSource,
                    extraArguments: profile.bridgeExtraArguments + ["--event", event.name]
                )
                let existingEvent = hooks[event.name] as? [[String: Any]]
                hooks[event.name] = normalizedHookEntries(
                    existingEvent,
                    preferred: makeCopilotHookEntries(command: command, event: event)
                )
            }
            json["hooks"] = hooks
            writeJSONObject(json, to: url)
            return
        }

        let command = bridgeCommand(source: profile.bridgeSource, extraArguments: profile.bridgeExtraArguments)
        let preferredFirst =
            profile.id == "qoder-cli-hooks"
            || profile.id == "qoder-cn-cli-hooks"
            || profile.id == "codebuddy-cli-hooks"

        var hooks = removingIslandManagedHooks(from: json["hooks"] as? [String: Any] ?? [:], profile: profile)
        for event in activeEvents {
            let existingEvent = hooks[event.name] as? [[String: Any]]
            hooks[event.name] = normalizedHookEntries(
                existingEvent,
                preferred: makeHookEntries(command: command, event: event),
                preferredFirst: preferredFirst,
                profile: profile
            )
        }

        json["hooks"] = hooks
        if profile.id == "claude-hooks" {
            json["statusLine"] = installedClaudeStatusLineConfiguration(
                preserving: json["statusLine"] as? [String: Any]
            )
        }
        writeJSONObject(json, to: url)
    }

    nonisolated static func installedClaudeStatusLineConfiguration(
        preserving existingStatusLine: [String: Any]?
    ) -> [String: Any] {
        if let existingStatusLine, !isManagedStatusLine(existingStatusLine) {
            return existingStatusLine
        }

        return managedStatusLineConfiguration()
    }

    static func isManagedClaudeStatusLineConfigured() -> Bool {
        guard let profile = ClientProfileRegistry.managedHookProfile(id: "claude-hooks") else {
            return false
        }
        return profile.configurationURLs.contains { url in
            guard let data = try? Data(contentsOf: url),
                let json = HookConfigParser.parseJSONObject(from: data)
            else {
                return false
            }
            return isManagedStatusLine(json["statusLine"] as? [String: Any])
        }
    }

    private nonisolated static func managedStatusLineConfiguration() -> [String: Any] {
        [
            "type": "command",
            "command": statusLineCommand(),
        ]
    }

    private nonisolated static func statusLineCommand() -> String {
        islandSupportDirectory()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent(statusLineScriptName)
            .path
    }

    private nonisolated static func isManagedStatusLine(_ statusLine: [String: Any]?) -> Bool {
        guard let command = statusLine?["command"] as? String else {
            return false
        }

        return command == statusLineCommand()
            || command.contains("/.mac-island/bin/\(statusLineScriptName)")
            || command.contains("/.ping-island/bin/\(statusLineScriptName)")
    }

    private static func writeManagedPlugin(at url: URL, profile: ManagedHookClientProfile) {
        let content = managedPluginSource(for: profile)
        guard !content.isEmpty else { return }

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try? Data(content.utf8).write(to: url, options: .atomic)
    }

    private static func removeManagedPlugin(at url: URL, profile: ManagedHookClientProfile) {
        guard containsManagedPlugin(at: url, profile: profile) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    private static func containsManagedPlugin(at url: URL, profile: ManagedHookClientProfile) -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }

        return content.contains(managedMarker(for: profile))
    }

    private static func writeManagedPluginDirectory(at url: URL, profile: ManagedHookClientProfile) {
        let files = managedPluginDirectoryFiles(for: profile)
        guard !files.isEmpty else { return }

        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, content) in files {
            let fileURL = url.appendingPathComponent(name)
            try? Data(content.utf8).write(to: fileURL, options: .atomic)
        }
    }

    private static func removeManagedPluginDirectory(at url: URL, profile: ManagedHookClientProfile) {
        guard containsManagedPluginDirectory(at: url, profile: profile) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    private static func containsManagedPluginDirectory(at url: URL, profile: ManagedHookClientProfile) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }

        let marker = managedMarker(for: profile)
        let candidates = [
            url.appendingPathComponent("plugin.yaml"),
            url.appendingPathComponent("plugin.json"),
            url.appendingPathComponent("hooks.json"),
            url.appendingPathComponent("__init__.py"),
            url.appendingPathComponent("index.ts"),
            url.appendingPathComponent("index.mjs"),
        ]

        return candidates.contains { fileURL in
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return false
            }
            return content.contains(marker)
        }
    }

    private static func writeManagedHookDirectory(at url: URL, profile: ManagedHookClientProfile) {
        let files = managedHookDirectoryFiles(for: profile)
        guard !files.isEmpty else { return }

        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, content) in files {
            let fileURL = url.appendingPathComponent(name)
            try? Data(content.utf8).write(to: fileURL, options: .atomic)
        }
    }

    private static func removeManagedHookDirectory(at url: URL, profile: ManagedHookClientProfile) {
        guard containsManagedHookDirectory(at: url, profile: profile) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    private static func containsManagedHookDirectory(at url: URL, profile: ManagedHookClientProfile) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }

        let marker = managedMarker(for: profile)
        let candidates = [
            url.appendingPathComponent("HOOK.md"),
            url.appendingPathComponent("handler.ts"),
        ]

        return candidates.contains { fileURL in
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return false
            }
            return content.contains(marker)
        }
    }

    private nonisolated static func makeHookEntries(command: String, event: HookInstallEventDescriptor) -> [[String:
        Any]]
    {
        var hookCommand: [String: Any] = [
            "type": "command",
            "command": command,
        ]
        if let timeout = event.timeout {
            hookCommand["timeout"] = timeout
        }

        return event.templates.map { template in
            switch template {
            case .plain:
                return ["hooks": [hookCommand]]
            case .matcher(let matcher):
                return [
                    "matcher": matcher,
                    "hooks": [hookCommand],
                ]
            case .direct:
                return hookCommand
            }
        }
    }

    private static func makeCopilotHookEntries(command: String, event: HookInstallEventDescriptor) -> [[String: Any]] {
        var entry: [String: Any] = [
            "type": "command",
            "bash": command,
        ]
        if let timeout = event.timeout {
            entry["timeoutSec"] = timeout
        }
        return [entry]
    }

    private nonisolated static func islandSupportDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
    }

    private static func bridgeCommandArguments(for profile: ManagedHookClientProfile) -> [String] {
        [
            islandSupportDirectory()
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent(bridgeLauncherName)
                .path,
            "--source",
            profile.bridgeSource,
        ] + profile.bridgeExtraArguments
    }

    private static func bridgeCommand(source: String, extraArguments: [String] = []) -> String {
        let launcherPath = islandSupportDirectory()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent(bridgeLauncherName)
            .path
        return ([launcherPath, "--source", source] + extraArguments)
            .map(shellQuotedIfNeeded)
            .joined(separator: " ")
    }

    private static func containsManagedHooks(at url: URL, profile: ManagedHookClientProfile? = nil) -> Bool {
        guard let data = try? Data(contentsOf: url),
            let json = HookConfigParser.parseJSONObject(from: data),
            let hooks = json["hooks"] as? [String: Any]
        else {
            return false
        }

        for (_, value) in hooks {
            if let entries = value as? [[String: Any]] {
                for entry in entries {
                    if isIslandManagedHookEntry(entry, for: profile) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private nonisolated static func isIslandManagedHookEntry(
        _ entry: [String: Any],
        for profile: ManagedHookClientProfile? = nil
    ) -> Bool {
        if let command = hookCommandString(from: entry) {
            return isIslandManagedHookCommand(command, for: profile)
        }

        if let nestedHooks = entry["hooks"] as? [[String: Any]] {
            return nestedHooks.contains { hook in
                guard let command = hookCommandString(from: hook) else { return false }
                return isIslandManagedHookCommand(command, for: profile)
            }
        }

        return false
    }

    private nonisolated static func hookCommandString(from entry: [String: Any]) -> String? {
        let candidates = [
            entry["command"] as? String,
            entry["bash"] as? String,
            entry["powershell"] as? String,
        ]
        return candidates.compactMap { command in
            let trimmed = command?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty == false) ? trimmed : nil
        }.first
    }

    private nonisolated static func isIslandManagedHookCommand(
        _ command: String,
        for profile: ManagedHookClientProfile? = nil
    ) -> Bool {
        let normalized = command.lowercased()
        let isManaged = normalized.contains("/.mac-island/bin/mac-island-bridge")
        guard isManaged, let profile else {
            return isManaged
        }

        switch profile.id {
        case "codebuddy-hooks":
            return hookCommand(command, hasClientKind: "codebuddy")
        case "codebuddy-cli-hooks":
            return hookCommand(command, hasClientKind: "codebuddy-cli")
        case "workbuddy-hooks":
            return hookCommand(command, hasClientKind: "workbuddy")
        case "qoder-hooks":
            return hookCommand(command, hasClientKind: "qoder")
        case "qoder-cli-hooks":
            return hookCommand(command, hasClientKind: "qoder-cli")
        case "qoder-cn-hooks":
            return hookCommand(command, hasClientKind: "qoder-cn")
        case "qoder-cn-cli-hooks":
            return hookCommand(command, hasClientKind: "qoder-cn-cli")
        case "qoderwork-hooks":
            return hookCommand(command, hasClientKind: "qoderwork")
        default:
            return true
        }
    }

    private nonisolated static func hookCommand(_ command: String, hasClientKind clientKind: String) -> Bool {
        let escapedKind = NSRegularExpression.escapedPattern(for: clientKind)
        let pattern = #"(^|\s)--client-kind\s+(?:'\#(escapedKind)'|"\#(escapedKind)"|\#(escapedKind))(?=\s|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(command.startIndex..., in: command)
        return regex.firstMatch(in: command, range: range) != nil
    }

    private static func managedMarker(for profile: ManagedHookClientProfile) -> String {
        "Mac Island managed integration: \(profile.id)"
    }

    static func managedPluginSource(for profile: ManagedHookClientProfile) -> String {
        guard profile.id == "opencode-hooks" else {
            return ""
        }

        let argsData =
            (try? JSONSerialization.data(withJSONObject: bridgeCommandArguments(for: profile), options: []))
            ?? Data("[]".utf8)
        let argsJSON = String(data: argsData, encoding: .utf8) ?? "[]"
        let marker = managedMarker(for: profile)

        return """
            // \(marker)
            // Generated by Mac Island. This plugin only observes and forwards local state.

            const BRIDGE_ARGS = \(argsJSON);
            const ENV_KEYS = [
              "TERM_PROGRAM",
              "ITERM_SESSION_ID",
              "TERM_SESSION_ID",
              "TMUX",
              "TMUX_PANE",
              "KITTY_WINDOW_ID",
              "__CFBundleIdentifier",
              "CONDUCTOR_WORKSPACE_NAME",
              "CONDUCTOR_PORT",
              "CURSOR_TRACE_ID",
              "CMUX_WORKSPACE_ID",
              "CMUX_SURFACE_ID",
              "CMUX_SOCKET_PATH",
              "WINDOWSERVER_DISPLAY_UUID"
            ];

            function isObject(value) {
              return value !== null && typeof value === "object" && !Array.isArray(value);
            }

            function atPath(value, path) {
              let current = value;
              for (const key of path) {
                if (!isObject(current) && !Array.isArray(current)) return undefined;
                current = current?.[key];
              }
              return current;
            }

            function firstDefined(value, paths) {
              for (const path of paths) {
                const candidate = atPath(value, path);
                if (candidate !== undefined && candidate !== null && candidate !== "") {
                  return candidate;
                }
              }
              return undefined;
            }

            function firstString(value, keys, depth = 0) {
              if (depth > 5 || value == null) return undefined;
              if (typeof value === "string" && value.trim().length > 0) return value;
              if (Array.isArray(value)) {
                for (const entry of value) {
                  const found = firstString(entry, keys, depth + 1);
                  if (found) return found;
                }
                return undefined;
              }
              if (!isObject(value)) return undefined;

              for (const key of keys) {
                const candidate = value[key];
                if (typeof candidate === "string" && candidate.trim().length > 0) {
                  return candidate;
                }
              }

              for (const nested of Object.values(value)) {
                const found = firstString(nested, keys, depth + 1);
                if (found) return found;
              }
              return undefined;
            }

            function stableString(value) {
              if (value == null) return undefined;
              if (typeof value === "string") {
                const trimmed = value.trim();
                return trimmed.length > 0 ? trimmed : undefined;
              }
              try {
                return JSON.stringify(value);
              } catch {
                return undefined;
              }
            }

            function capitalize(value) {
              if (typeof value !== "string" || value.length === 0) return undefined;
              return value.charAt(0).toUpperCase() + value.slice(1);
            }

            function collectBridgeEnv() {
              const collected = {};
              for (const key of ENV_KEYS) {
                const value = process.env[key];
                if (typeof value === "string" && value.length > 0) {
                  collected[key] = value;
                }
              }
              return collected;
            }

            function detectTTY() {
              try {
                const { execSync } = require("child_process");
                let walkPid = process.pid;
                for (let index = 0; index < 8; index += 1) {
                  const info = execSync(`ps -o tty=,ppid= -p ${walkPid}`, { timeout: 1000 })
                    .toString()
                    .trim();
                  if (!info) break;
                  const parts = info.split(/\\s+/);
                  const tty = parts[0];
                  const ppid = Number.parseInt(parts[1] || "", 10);
                  if (tty && tty !== "??" && tty !== "?") {
                    return tty.startsWith("/dev/") ? tty : `/dev/${tty}`;
                  }
                  if (!Number.isFinite(ppid) || ppid <= 1) break;
                  walkPid = ppid;
                }
              } catch {
                return undefined;
              }
              return undefined;
            }

            function makeBasePayload(sessionId, extra = {}) {
              const routedSessionID = rootSessionID(sessionId);
              const session = sessions.get(routedSessionID) ?? sessions.get(sessionId);
              return {
                session_id: routedSessionID,
                _source: "opencode",
                platform: process.env.__CFBundleIdentifier === "ai.opencode.desktop" ? "desktop" : "cli",
                _env: collectBridgeEnv(),
                _tty: detectedTTY,
                pid: process.pid,
                provider_name: session?.provider,
                model: session?.model,
                ...extra
              };
            }

            function toolNameForPermission(permission) {
              if (permission === "bash") return "Bash";
              if (permission === "edit" || permission === "write") return "Write";
              return capitalize(permission) ?? "Permission";
            }

            function mapEvent(event) {
              const type = event?.type;
              const properties = isObject(event?.properties) ? event.properties : {};
              if (typeof type !== "string" || type.length === 0) return undefined;

              if (type === "session.created" && isObject(properties.info) && stableString(properties.info.id)) {
                const rawSessionID = stableString(properties.info.id);
                const cwd = stableString(properties.info.directory);
                const session = getSession(rawSessionID);
                session.cwd = cwd;
                session.parentID = stableString(properties.info.parentID);
                if (session.parentID) {
                  const parent = getSession(session.parentID);
                  if (!parent.cwd && cwd) parent.cwd = cwd;
                  return makeBasePayload(session.parentID, {
                    hook_event_name: "SubagentStart",
                    cwd: parent.cwd ?? cwd,
                    tool_name: stableString(properties.info.title) ?? "Subagent",
                    tool_use_id: rawSessionID
                  });
                }
                return makeBasePayload(rawSessionID, {
                  hook_event_name: "SessionStart",
                  cwd,
                  session_title: stableString(properties.info.title)
                });
              }

              if (type === "session.deleted" && isObject(properties.info) && stableString(properties.info.id)) {
                const rawSessionID = stableString(properties.info.id);
                const session = getSession(rawSessionID);
                const parentID = stableString(session.parentID)
                  ?? stableString(properties.info.parentID);
                sessions.delete(rawSessionID);
                messageRoles.forEach((value, key) => {
                  if (value?.sessionID === rawSessionID) {
                    messageRoles.delete(key);
                  }
                });
                if (parentID) {
                  return makeBasePayload(parentID, {
                    hook_event_name: "SubagentStop",
                    tool_name: stableString(properties.info.title) ?? "Subagent",
                    tool_use_id: rawSessionID
                  });
                }
                return makeBasePayload(rawSessionID, {
                  hook_event_name: "SessionEnd"
                });
              }

              if (type === "session.updated" && isObject(properties.info) && stableString(properties.info.id)) {
                const rawSessionID = stableString(properties.info.id);
                const session = getSession(rawSessionID);
                session.parentID = stableString(properties.info.parentID) ?? session.parentID;
                const cwd = stableString(properties.info.directory) ?? session.cwd;
                if (cwd) session.cwd = cwd;
                const title = stableString(properties.info.title);
                if (title && !title.startsWith("New session")) {
                  session.pendingTitle = title;
                }
                if (properties.info.time?.archived) {
                  sessions.delete(rawSessionID);
                  return makeBasePayload(session.parentID ?? rawSessionID, {
                    hook_event_name: session.parentID ? "SubagentStop" : "SessionEnd",
                    tool_name: session.parentID ? (title ?? "Subagent") : undefined,
                    tool_use_id: session.parentID ? rawSessionID : undefined,
                    cwd
                  });
                }
                return undefined;
              }

              if ((type === "session.status" || type === "session.idle") && stableString(properties.sessionID)) {
                const rawSessionID = stableString(properties.sessionID);
                const session = getSession(rawSessionID);
                if (type === "session.idle" || properties.status?.type === "idle") {
                  if (isChildSession(rawSessionID)) {
                    if (session.subagentEnded) return undefined;
                    session.subagentEnded = true;
                    return makeBasePayload(rawSessionID, {
                      hook_event_name: "SubagentStop",
                      cwd: sessions.get(rootSessionID(rawSessionID))?.cwd ?? session.cwd,
                      tool_name: "Subagent",
                      tool_use_id: rawSessionID
                    });
                  }
                  const payload = makeBasePayload(rawSessionID, {
                    hook_event_name: "Stop",
                    cwd: session.cwd,
                    last_assistant_message: session.lastAssistantText || undefined,
                    session_title: session.pendingTitle || undefined
                  });
                  session.pendingTitle = undefined;
                  return payload;
                }
                return undefined;
              }

              if (type === "message.updated" && isObject(properties.info) && stableString(properties.info.id) && stableString(properties.info.sessionID)) {
                messageRoles.set(stableString(properties.info.id), {
                  role: stableString(properties.info.role),
                  sessionID: stableString(properties.info.sessionID),
                  provider: stableString(properties.info.providerID)
                    ?? stableString(properties.info.provider?.id),
                  model: stableString(properties.info.modelID)
                    ?? stableString(properties.info.model?.id)
                });
                const session = getSession(stableString(properties.info.sessionID));
                const meta = messageRoles.get(stableString(properties.info.id));
                if (meta?.provider) session.provider = meta.provider;
                if (meta?.model) session.model = meta.model;
                if (messageRoles.size > 200) {
                  messageRoles.delete(messageRoles.keys().next().value);
                }
                return undefined;
              }

              if (type === "message.part.updated" && isObject(properties.part) && stableString(properties.part.sessionID)) {
                const rawSessionID = stableString(properties.part.sessionID);
                const session = getSession(rawSessionID);
                const sessionId = rootSessionID(rawSessionID);

                if (properties.part.type === "text" && stableString(properties.part.messageID)) {
                  if (isChildSession(rawSessionID)) return undefined;
                  const meta = messageRoles.get(stableString(properties.part.messageID));
                  if (!meta) return undefined;

                  const text = stableString(properties.part.text);
                  if (!text) return undefined;

                  if (meta.role === "user") {
                    session.lastUserText = text;
                    return makeBasePayload(sessionId, {
                      hook_event_name: "UserPromptSubmit",
                      cwd: session.cwd,
                      prompt: text
                    });
                  }

                  if (meta.role === "assistant") {
                    session.lastAssistantText = text;
                  }
                  return undefined;
                }

                if (properties.part.type === "tool") {
                  const toolName = capitalize(stableString(properties.part.tool)) ?? "Tool";
                  const state = stableString(properties.part.state?.status);
                  if (state === "running" || state === "pending") {
                    return makeBasePayload(sessionId, {
                      hook_event_name: "PreToolUse",
                      cwd: session.cwd,
                      tool_name: toolName,
                      tool_use_id: stableString(properties.part.id)
                        ?? stableString(properties.part.callID)
                    });
                  }
                  if (state === "completed" || state === "error") {
                    return makeBasePayload(sessionId, {
                      hook_event_name: state === "error" ? "PostToolUseFailure" : "PostToolUse",
                      cwd: session.cwd,
                      tool_name: toolName,
                      tool_use_id: stableString(properties.part.id)
                        ?? stableString(properties.part.callID)
                    });
                  }
                }

                if (properties.part.type === "subtask" || properties.part.type === "agent") {
                  const ended = properties.part.time?.end != null
                    || properties.part.state?.status === "completed"
                    || properties.part.state?.status === "error";
                  return makeBasePayload(sessionId, {
                    hook_event_name: ended ? "SubagentStop" : "SubagentStart",
                    cwd: sessions.get(sessionId)?.cwd ?? session.cwd,
                    tool_name: stableString(properties.part.agent)
                      ?? stableString(properties.part.description)
                      ?? "Subagent",
                    tool_use_id: stableString(properties.part.id)
                  });
                }
              }

              if (["permission.asked", "permission.updated", "permission.v2.asked"].includes(type)
                  && stableString(properties.id) && stableString(properties.sessionID)) {
                const rawSessionID = stableString(properties.sessionID);
                const session = getSession(rawSessionID);
                return makeBasePayload(rawSessionID, {
                  hook_event_name: "PermissionRequest",
                  cwd: session.cwd,
                  tool_name: toolNameForPermission(
                    stableString(properties.permission)
                      ?? stableString(properties.action)
                      ?? stableString(properties.type)
                  ),
                  tool_use_id: stableString(properties.id)
                });
              }

              if ((type === "permission.replied" || type === "permission.v2.replied")
                  && stableString(properties.sessionID)) {
                const rawSessionID = stableString(properties.sessionID);
                const session = getSession(rawSessionID);
                return makeBasePayload(rawSessionID, {
                  hook_event_name: "PostToolUse",
                  cwd: session.cwd,
                  tool_name: toolNameForPermission(properties.permission)
                });
              }

              if ((type === "question.asked" || type === "question.v2.asked")
                  && stableString(properties.id) && stableString(properties.sessionID)) {
                const rawSessionID = stableString(properties.sessionID);
                const session = getSession(rawSessionID);
                return makeBasePayload(rawSessionID, {
                  hook_event_name: "PermissionRequest",
                  cwd: session.cwd,
                  tool_name: "AskUserQuestion",
                  tool_use_id: stableString(properties.id)
                });
              }

              if (["question.replied", "question.rejected", "question.v2.replied", "question.v2.rejected"].includes(type)
                  && stableString(properties.sessionID)) {
                const rawSessionID = stableString(properties.sessionID);
                const session = getSession(rawSessionID);
                return makeBasePayload(rawSessionID, {
                  hook_event_name: "PostToolUse",
                  cwd: session.cwd,
                  tool_name: "AskUserQuestion"
                });
              }

              if (type === "todo.updated" && stableString(properties.sessionID)) {
                const rawSessionID = stableString(properties.sessionID);
                const session = getSession(rawSessionID);
                const todos = Array.isArray(properties.todos) ? properties.todos : [];
                const latest = todos[todos.length - 1];
                const allCompleted = todos.length > 0 && todos.every((todo) => todo?.status === "completed");
                return makeBasePayload(rawSessionID, {
                  hook_event_name: allCompleted ? "TaskCompleted" : "TaskCreated",
                  cwd: session.cwd,
                  task_id: stableString(latest?.id),
                  message: stableString(latest?.content)
                });
              }

              if ((type === "session.error" || type === "error") && stableString(properties.sessionID)) {
                const rawSessionID = stableString(properties.sessionID);
                const session = getSession(rawSessionID);
                return makeBasePayload(rawSessionID, {
                  hook_event_name: "StopFailure",
                  cwd: session.cwd,
                  message: firstString(properties, ["message", "error", "detail"])
                });
              }

              return undefined;
            }

            function runBridge(payload) {
              const env = { ...(globalThis.process?.env ?? {}) };
              if (isObject(payload?._env)) {
                Object.assign(env, payload._env);
              }
              if (typeof payload?._tty === "string" && payload._tty.length > 0) {
                env.TTY = payload._tty;
              }

              try {
                const subprocess = Bun.spawn(BRIDGE_ARGS, {
                  stdin: new Response(JSON.stringify(payload)),
                  stdout: "ignore",
                  stderr: "ignore",
                  env
                });
                void subprocess.exited.catch(() => {});
              } catch {
                // OpenCode hooks should never fail because Island is unavailable.
              }
            }

            const detectedTTY = detectTTY();
            const messageRoles = new Map();
            const sessions = new Map();

            function getSession(sessionID) {
              if (!sessions.has(sessionID)) {
                sessions.set(sessionID, {
                  cwd: undefined,
                  parentID: undefined,
                  subagentEnded: false,
                  lastUserText: "",
                  lastAssistantText: "",
                  pendingTitle: undefined
                });
              }
              return sessions.get(sessionID);
            }

            function rootSessionID(sessionID) {
              let current = sessionID;
              const visited = new Set();
              for (let index = 0; index < 8; index += 1) {
                if (!current || visited.has(current)) break;
                visited.add(current);
                const parentID = stableString(sessions.get(current)?.parentID);
                if (!parentID) break;
                current = parentID;
              }
              return current || sessionID;
            }

            function isChildSession(sessionID) {
              return rootSessionID(sessionID) !== sessionID;
            }

            export const server = async () => {
              return {
              name: "Mac Island",
              description: "Observe OpenCode activity in Mac Island.",
              event: async ({ event }) => {
                const payload = mapEvent(event);
                if (!payload) return;
                runBridge(payload);
              },
              "shell.env": async (_input, output) => {
                for (const key of ENV_KEYS) {
                  const value = process.env[key];
                  if (typeof value === "string" && value.length > 0) {
                    output.env[key] = value;
                  }
                }
                if (detectedTTY) {
                  output.env.TTY = detectedTTY;
                }
              }
            };

            };

            export default server;
            """
    }

    static func managedDSHPluginSource(for profile: ManagedHookClientProfile) -> String {
        guard profile.id == "dsh-hooks" else { return "" }

        let argsData =
            (try? JSONSerialization.data(
                withJSONObject: bridgeCommandArguments(for: profile),
                options: []
            )) ?? Data("[]".utf8)
        let argsJSON = String(data: argsData, encoding: .utf8) ?? "[]"
        let marker = managedMarker(for: profile)

        return """
            // \(marker)
            // Generated by Mac Island. Observation only: never approves, replies, or changes DSH behavior.

            import { execFileSync, spawn } from "node:child_process";

            export const name = "mac-island-observer";
            const BRIDGE_ARGS = \(argsJSON);
            const ENV_KEYS = [
              "TERM_PROGRAM",
              "ITERM_SESSION_ID",
              "TERM_SESSION_ID",
              "TMUX",
              "TMUX_PANE",
              "KITTY_WINDOW_ID",
              "__CFBundleIdentifier",
              "CONDUCTOR_WORKSPACE_NAME",
              "CONDUCTOR_PORT",
              "CURSOR_TRACE_ID",
              "CMUX_WORKSPACE_ID",
              "CMUX_SURFACE_ID",
              "CMUX_SOCKET_PATH",
              "WINDOWSERVER_DISPLAY_UUID"
            ];
            const sessions = new Map();
            const agentSessions = new WeakMap();

            function stableString(value) {
              if (typeof value !== "string") return undefined;
              const trimmed = value.trim();
              return trimmed.length > 0 ? trimmed : undefined;
            }

            function stringID(value) {
              if (value == null) return undefined;
              return stableString(String(value));
            }

            function collectEnvironment() {
              const result = {};
              for (const key of ENV_KEYS) {
                const value = process.env[key];
                if (typeof value === "string" && value.length > 0) result[key] = value;
              }
              return result;
            }

            function detectTTY() {
              try {
                let pid = process.pid;
                for (let index = 0; index < 8; index += 1) {
                  const output = execFileSync("/bin/ps", ["-o", "tty=,ppid=", "-p", String(pid)], {
                    encoding: "utf8",
                    timeout: 800
                  }).trim();
                  if (!output) break;
                  const parts = output.split(/\\s+/);
                  const tty = parts[0];
                  const parent = Number.parseInt(parts[1] ?? "", 10);
                  if (tty && tty !== "?" && tty !== "??") {
                    return tty.startsWith("/dev/") ? tty : `/dev/${tty}`;
                  }
                  if (!Number.isFinite(parent) || parent <= 1) break;
                  pid = parent;
                }
              } catch {
                return undefined;
              }
              return undefined;
            }

            function profileMode() {
              const explicitIndex = process.argv.indexOf("--profile");
              if (explicitIndex >= 0) return stableString(process.argv[explicitIndex + 1]) ?? "cli";
              if (process.argv.some((part) => part === "web")) return "web";
              if (process.argv.some((part) => part === "headless")) return "headless";
              if (process.argv.some((part) => part === "tui")) return "tui";
              return "cli";
            }

            function localWebURL() {
              const index = process.argv.indexOf("--port");
              const rawPort = index >= 0 ? process.argv[index + 1] : undefined;
              const port = Number.parseInt(rawPort ?? "3080", 10);
              return `http://127.0.0.1:${Number.isFinite(port) ? port : 3080}`;
            }

            const mode = profileMode();
            const platform = mode === "web" ? "web" : "cli";
            const detectedTTY = detectTTY();

            function stateFor(sessionLike) {
              const id = stringID(sessionLike?.id ?? sessionLike);
              if (!id) return undefined;
              if (!sessions.has(id)) {
                sessions.set(id, {
                  id,
                  cwd: undefined,
                  parentID: undefined,
                  isChild: false,
                  started: false,
                  subagentStarted: false,
                  subagentEnded: false,
                  running: false,
                  turnEnded: false,
                  provider: undefined,
                  model: undefined,
                  title: undefined,
                  lastAssistant: undefined,
                  tools: new Map()
                });
              }
              const state = sessions.get(id);
              const header = sessionLike?.header;
              if (header && typeof header === "object") {
                state.cwd = stableString(header.cwd) ?? state.cwd;
                state.parentID = stringID(header.parentSession) ?? state.parentID;
                state.isChild = header.origin === "subagent" && Boolean(state.parentID);
              }
              return state;
            }

            function rootID(id) {
              let current = id;
              const visited = new Set();
              for (let index = 0; index < 8; index += 1) {
                if (!current || visited.has(current)) break;
                visited.add(current);
                const parent = sessions.get(current)?.parentID;
                if (!parent) break;
                current = parent;
              }
              return current ?? id;
            }

            function rootState(state) {
              const id = rootID(state.id);
              return sessions.get(id) ?? stateFor(id);
            }

            function textContent(message) {
              const blocks = Array.isArray(message?.content) ? message.content : [];
              const text = blocks
                .filter((block) => block && block.type === "text" && typeof block.text === "string")
                .map((block) => block.text.trim())
                .filter(Boolean)
                .join("\\n");
              return stableString(text);
            }

            function shortTitle(text) {
              const firstLine = stableString(text)?.split("\\n")[0]?.trim();
              if (!firstLine) return undefined;
              return firstLine.length > 72 ? `${firstLine.slice(0, 71)}…` : firstLine;
            }

            function bridgePayload(state, extra = {}) {
              const routed = rootState(state);
              return {
                session_id: routed.id,
                _source: "dsh",
                platform,
                client_name: platform === "web" ? "DeepSeek Harness Web" : "DeepSeek Harness",
                client_originator: "DeepSeek Harness",
                thread_source: "dsh-plugin",
                source_process_name: "dsh",
                launch_url: platform === "web" ? localWebURL() : undefined,
                cwd: routed.cwd ?? state.cwd ?? process.cwd(),
                provider_name: routed.provider ?? state.provider,
                model: routed.model ?? state.model,
                session_title: routed.title,
                _env: collectEnvironment(),
                _tty: detectedTTY,
                pid: process.pid,
                ...extra
              };
            }

            function runBridge(payload) {
              if (!Array.isArray(BRIDGE_ARGS) || BRIDGE_ARGS.length === 0) return;
              try {
                const child = spawn(BRIDGE_ARGS[0], BRIDGE_ARGS.slice(1), {
                  stdio: ["pipe", "ignore", "ignore"],
                  env: process.env,
                  detached: true
                });
                child.on("error", () => {});
                child.stdin?.on("error", () => {});
                child.stdin?.end(JSON.stringify(payload));
                child.unref();
              } catch {
                // Mac Island being unavailable must never affect DSH.
              }
            }

            function emitStart(sessionLike) {
              const state = stateFor(sessionLike);
              if (!state) return;
              const routed = rootState(state);
              if (state.isChild) {
                if (state.subagentStarted) return;
                state.subagentStarted = true;
                runBridge(bridgePayload(state, {
                  hook_event_name: "SubagentStart",
                  tool_name: "Subagent",
                  tool_use_id: state.id,
                  message: "DeepSeek Harness 子 Agent 已开始"
                }));
                return;
              }
              if (routed.started) return;
              routed.started = true;
              runBridge(bridgePayload(routed, { hook_event_name: "SessionStart" }));
            }

            function updateModel(state, provider, model) {
              const routed = rootState(state);
              const normalizedProvider = stableString(provider);
              const normalizedModel = stableString(model);
              if (normalizedProvider) {
                state.provider = normalizedProvider;
                routed.provider = normalizedProvider;
              }
              if (normalizedModel) {
                state.model = normalizedModel;
                routed.model = normalizedModel;
              }
            }

            function emitSubagentStop(state) {
              if (!state.isChild || state.subagentEnded) return;
              state.subagentEnded = true;
              runBridge(bridgePayload(state, {
                hook_event_name: "SubagentStop",
                tool_name: "Subagent",
                tool_use_id: state.id,
                message: "DeepSeek Harness 子 Agent 已完成"
              }));
            }

            function handleSessionEvent(session, event) {
              const state = stateFor(session);
              const type = stableString(event?.type);
              const data = event?.data ?? {};
              if (!state || !type) return;

              if (type === "turn/start") {
                state.running = true;
                state.turnEnded = false;
                emitStart(session);
                return;
              }

              if (type === "user/message") {
                if (data?.source?.kind !== "user" || state.isChild) return;
                emitStart(session);
                const prompt = textContent(data);
                if (!prompt) return;
                const routed = rootState(state);
                routed.title = routed.title ?? shortTitle(prompt);
                runBridge(bridgePayload(state, {
                  hook_event_name: "UserPromptSubmit",
                  prompt,
                  session_title: routed.title
                }));
                return;
              }

              if (type === "request/context") {
                updateModel(state, data.provider, data.model);
                return;
              }

              if (type === "request/header") {
                updateModel(state, data?.header?.config?.provider, data?.header?.config?.model);
                return;
              }

              if (type === "assistant/message") {
                emitStart(session);
                const message = data.message;
                updateModel(state, message?.source?.provider, message?.source?.model);
                const reply = textContent(message);
                if (!reply) return;
                const routed = rootState(state);
                routed.lastAssistant = state.isChild ? `子 Agent：${reply}` : reply;
                runBridge(bridgePayload(state, {
                  hook_event_name: "Notification",
                  notification_type: "assistant_message",
                  message: routed.lastAssistant
                }));
                return;
              }

              if (type === "tool/call") {
                emitStart(session);
                const callID = stringID(data.callId) ?? `dsh-tool-${event.seq ?? Date.now()}`;
                const toolName = stableString(data.name) ?? "Tool";
                state.tools.set(callID, toolName);
                const asksUser = ["askuserquestion", "ask_user_question", "question"].includes(toolName.toLowerCase());
                runBridge(bridgePayload(state, {
                  hook_event_name: asksUser ? "PermissionRequest" : "PreToolUse",
                  tool_name: asksUser ? "AskUserQuestion" : toolName,
                  tool_use_id: callID
                }));
                return;
              }

              if (type === "tool/result") {
                emitStart(session);
                const callID = stringID(data?.message?.source?.callId) ?? `dsh-tool-${event.seq ?? Date.now()}`;
                const toolName = state.tools.get(callID) ?? "Tool";
                const isError = Boolean(data.error) || data?.message?.content?.some((block) => block?.isError === true);
                runBridge(bridgePayload(state, {
                  hook_event_name: isError ? "PostToolUseFailure" : "PostToolUse",
                  tool_name: toolName,
                  tool_use_id: callID,
                  error: isError ? "Tool failed" : undefined
                }));
                state.tools.delete(callID);
                return;
              }

              if (type === "approval/asked") {
                emitStart(session);
                runBridge(bridgePayload(state, {
                  hook_event_name: "PermissionRequest",
                  tool_name: stableString(data.toolName) ?? "Approval",
                  tool_use_id: stringID(data.id)
                }));
                return;
              }

              if (type === "approval/decided") {
                runBridge(bridgePayload(state, {
                  hook_event_name: "PostToolUse",
                  tool_name: stableString(data.toolName) ?? "Approval",
                  tool_use_id: stringID(data.id)
                }));
                return;
              }

              if (type === "todo/write") {
                const todos = Array.isArray(data.todos) ? data.todos : [];
                const item = todos.find((todo) => todo?.status === "in_progress")
                  ?? todos.find((todo) => todo?.status === "pending")
                  ?? [...todos].reverse().find((todo) => todo?.status === "completed");
                const content = stableString(item?.content);
                if (!content) return;
                runBridge(bridgePayload(state, {
                  hook_event_name: item.status === "completed" ? "TaskCompleted" : "TaskCreated",
                  message: content,
                  tool_name: "Todo"
                }));
                return;
              }

              if (type === "turn/end") {
                state.running = false;
                state.turnEnded = true;
                if (state.isChild) {
                  emitSubagentStop(state);
                  return;
                }
                const reason = stableString(data?.reason?.kind) ?? "completed";
                const failed = !["completed", "max-tokens"].includes(reason);
                const routed = rootState(state);
                runBridge(bridgePayload(state, {
                  hook_event_name: failed ? "StopFailure" : "Stop",
                  last_assistant_message: routed.lastAssistant,
                  message: failed ? `DeepSeek Harness 已停止（${reason}）` : routed.lastAssistant,
                  error: failed ? "Turn failed" : undefined
                }));
              }
            }

            export function apply(ctx) {
              ctx.on("agent/created", ({ agent }) => {
                const state = stateFor(agent?.session);
                if (!state) return;
                agentSessions.set(agent, state.id);
                emitStart(agent.session);
              });

              ctx.on("agent/session-start", ({ agent }) => {
                emitStart(agent?.session);
              });

              ctx.on("agent/status", ({ agent, status }) => {
                const id = agentSessions.get(agent) ?? stringID(agent?.session?.id);
                const state = stateFor(agent?.session ?? id);
                if (!state) return;
                if (status === "running") {
                  state.running = true;
                  state.turnEnded = false;
                  emitStart(agent.session);
                } else if (status === "idle" && state.running && !state.turnEnded && !state.isChild) {
                  state.running = false;
                  runBridge(bridgePayload(state, {
                    hook_event_name: "Stop",
                    last_assistant_message: rootState(state).lastAssistant
                  }));
                }
              });

              ctx.on("agent/error", ({ agent }) => {
                const state = stateFor(agent?.session);
                if (!state) return;
                state.running = false;
                runBridge(bridgePayload(state, {
                  hook_event_name: "StopFailure",
                  message: "DeepSeek Harness 执行失败",
                  error: "Agent failed"
                }));
              });

              ctx.on("agent/disposed", ({ agent }) => {
                const id = agentSessions.get(agent) ?? stringID(agent?.session?.id);
                const state = stateFor(agent?.session ?? id);
                if (!state) return;
                if (state.isChild) {
                  emitSubagentStop(state);
                } else if (state.started) {
                  runBridge(bridgePayload(state, { hook_event_name: "SessionEnd" }));
                }
                sessions.delete(state.id);
              });

              ctx.on("session/event", handleSessionEvent);
            }
            """
    }

    static func managedPluginDirectoryFiles(
        for profile: ManagedHookClientProfile,
        bridgeArguments: [String]? = nil,
        bridgeEnvironment: [String: String] = [:]
    ) -> [String: String] {
        if profile.id == "antigravity-hooks" {
            return managedAntigravityPluginFiles(
                for: profile,
                bridgeArguments: bridgeArguments,
                bridgeEnvironment: bridgeEnvironment
            )
        }

        if profile.id == "pi-hooks" {
            return ["index.ts": managedPiExtensionSource(for: profile)]
        }

        if profile.id == "dsh-hooks" {
            return ["index.mjs": managedDSHPluginSource(for: profile)]
        }

        guard profile.id == "hermes-hooks" else {
            return [:]
        }

        let argsData =
            (try? JSONSerialization.data(withJSONObject: bridgeCommandArguments(for: profile), options: []))
            ?? Data("[]".utf8)
        let argsJSON = String(data: argsData, encoding: .utf8) ?? "[]"
        let marker = managedMarker(for: profile)

        let pluginYAML = """
            # \(marker)
            name: mac_island
            version: 1.0.0
            description: Observe Hermes Agent activity in Mac Island
            provides_hooks:
              - on_session_start
              - pre_llm_call
              - pre_tool_call
              - post_tool_call
              - post_llm_call
              - on_session_end
              - on_session_finalize
              - on_session_reset
              - subagent_start
              - subagent_stop
              - pre_approval_request
              - post_approval_response
            """

        let initPy = """
            # \(marker)
            \"\"\"Mac Island monitor-only Hermes plugin.

            Generated by Mac Island. Reinstall from Mac Island settings to refresh it.
            \"\"\"

            from __future__ import annotations

            import json
            import os
            import subprocess
            import threading

            BRIDGE_ARGS = json.loads(r'''\(argsJSON)''')
            ENV_KEYS = [
                "TERM_PROGRAM",
                "ITERM_SESSION_ID",
                "TERM_SESSION_ID",
                "TMUX",
                "TMUX_PANE",
                "KITTY_WINDOW_ID",
                "__CFBundleIdentifier",
                "CONDUCTOR_WORKSPACE_NAME",
                "CONDUCTOR_PORT",
                "CURSOR_TRACE_ID",
                "CMUX_WORKSPACE_ID",
                "CMUX_SURFACE_ID",
                "CMUX_SOCKET_PATH",
                "WINDOWSERVER_DISPLAY_UUID",
            ]
            _SESSION_STATE = {}


            def _stable_text(value):
                if value is None:
                    return None
                if isinstance(value, str):
                    stripped = value.strip()
                    return stripped or None
                try:
                    return json.dumps(value, ensure_ascii=False)
                except Exception:
                    return None


            def _payload_session_id(raw_value):
                normalized = _stable_text(raw_value)
                if not normalized:
                    return None
                # Preserve Hermes' native ID exactly so live hooks and the read-only
                # state.db recovery path resolve to the same Mac Island session key.
                return normalized


            def _collect_env():
                collected = {}
                for key in ENV_KEYS:
                    value = os.environ.get(key)
                    if value:
                        collected[key] = value
                return collected


            def _detect_tty():
                for fd in (0, 1, 2):
                    try:
                        value = os.ttyname(fd)
                    except OSError:
                        continue
                    if value:
                        return value
                return os.environ.get("TTY")


            def _state_for(session_id):
                if session_id not in _SESSION_STATE:
                    _SESSION_STATE[session_id] = {
                        "cwd": None,
                        "last_user": None,
                        "last_assistant": None,
                        "platform": None,
                        "model": None,
                        "provider": None,
                        "did_emit_start": False,
                    }
                return _SESSION_STATE[session_id]


            def _resolve_session_id(*candidates, **kwargs):
                for candidate in candidates:
                    resolved = _payload_session_id(candidate)
                    if resolved:
                        return resolved
                for key in ("session_id", "task_id", "conversation_id"):
                    resolved = _payload_session_id(kwargs.get(key))
                    if resolved:
                        return resolved
                return None


            def _resolve_cwd(kwargs):
                for key in ("cwd", "working_directory", "directory"):
                    resolved = _stable_text(kwargs.get(key))
                    if resolved:
                        return resolved
                try:
                    return os.getcwd()
                except OSError:
                    return None


            def _extract_user_message(kwargs):
                direct = _stable_text(kwargs.get("user_message"))
                if direct:
                    return direct

                # Hermes and other runtimes may pass user input under different keys.
                for key in ("prompt", "input", "query", "text", "content"):
                    candidate = _stable_text(kwargs.get(key))
                    if candidate:
                        return candidate

                history = kwargs.get("messages")
                if not isinstance(history, list):
                    history = kwargs.get("conversation_history")
                if isinstance(history, list):
                    for entry in reversed(history):
                        if not isinstance(entry, dict):
                            continue
                        role = _stable_text(entry.get("role"))
                        if role != "user":
                            continue
                        content = entry.get("content")
                        if isinstance(content, str):
                            return _stable_text(content)
                        if isinstance(content, list):
                            for item in content:
                                if isinstance(item, dict) and item.get("type") == "text":
                                    text = _stable_text(item.get("text"))
                                    if text:
                                        return text
                return None


            def _extract_assistant_message(kwargs):
                direct = _stable_text(kwargs.get("assistant_response"))
                if direct:
                    return direct

                response = kwargs.get("response")
                if isinstance(response, str):
                    normalized = _stable_text(response)
                    if normalized:
                        return normalized
                if isinstance(response, dict):
                    for key in ("content", "text", "response", "message"):
                        normalized = _stable_text(response.get(key))
                        if normalized:
                            return normalized
                return None


            def _parse_tool_result(result):
                if isinstance(result, str):
                    try:
                        parsed = json.loads(result)
                    except Exception:
                        return None, None
                    if isinstance(parsed, dict):
                        return parsed, _stable_text(parsed.get("error"))
                    return None, None
                if isinstance(result, dict):
                    return result, _stable_text(result.get("error"))
                return None, None


            def _bridge_payload(session_id, **payload):
                state = _state_for(session_id)
                cwd = payload.pop("cwd", None) or state.get("cwd")
                if cwd:
                    state["cwd"] = cwd
                return {
                    "session_id": session_id,
                    "_env": _collect_env(),
                    "_tty": _detect_tty(),
                    "cwd": cwd,
                    "platform": state.get("platform"),
                    "model": state.get("model"),
                    "provider_name": state.get("provider"),
                    **payload,
                }


            def _spawn_bridge(payload):
                env = os.environ.copy()
                bridged_env = payload.pop("_env", None)
                tty = payload.pop("_tty", None)
                if isinstance(bridged_env, dict):
                    env.update({key: value for key, value in bridged_env.items() if isinstance(value, str) and value})
                if tty and not env.get("TTY"):
                    env["TTY"] = tty

                try:
                    process = subprocess.Popen(
                        BRIDGE_ARGS,
                        stdin=subprocess.PIPE,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        text=True,
                        env=env,
                        start_new_session=True,
                    )
                    if process.stdin:
                        process.stdin.write(json.dumps(payload, ensure_ascii=False))
                        process.stdin.close()
                except Exception:
                    return


            def _emit(payload):
                threading.Thread(target=_spawn_bridge, args=(payload,), daemon=True).start()


            def _emit_session_start(session_id, platform=None, model=None, message=None, cwd=None):
                state = _state_for(session_id)
                if state.get("did_emit_start"):
                    return

                normalized_platform = _stable_text(platform) or state.get("platform")
                if normalized_platform not in ("cli", "desktop"):
                    return
                state["platform"] = normalized_platform
                if _stable_text(model):
                    state["model"] = _stable_text(model)

                _emit(
                    _bridge_payload(
                        session_id,
                        hook_event_name="SessionStart",
                        platform=_stable_text(platform),
                        model=_stable_text(model),
                        message=_stable_text(message),
                        cwd=cwd,
                    )
                )
                state["did_emit_start"] = True


            def _on_session_start(session_id=None, platform=None, model=None, **kwargs):
                resolved_id = _resolve_session_id(session_id, **kwargs)
                if not resolved_id:
                    return
                _emit_session_start(
                    resolved_id,
                    platform=platform,
                    model=model,
                    message=_extract_user_message(kwargs),
                    cwd=_resolve_cwd(kwargs),
                )
                return None


            def _on_pre_llm_call(session_id=None, user_message=None, **kwargs):
                resolved_id = _resolve_session_id(session_id, kwargs.get("task_id"), **kwargs)
                if not resolved_id:
                    return None

                prompt = _stable_text(user_message) or _extract_user_message(kwargs)
                cwd = _resolve_cwd(kwargs)
                platform = _stable_text(kwargs.get("platform"))
                if platform not in ("cli", "desktop"):
                    return None
                state = _state_for(resolved_id)
                state["platform"] = platform
                state["model"] = _stable_text(kwargs.get("model")) or state.get("model")
                state["provider"] = _stable_text(kwargs.get("provider")) or state.get("provider")

                try:
                    _emit_session_start(
                        resolved_id,
                        platform=platform,
                        model=kwargs.get("model"),
                        message=prompt,
                        cwd=cwd,
                    )
                except Exception:
                    pass

                if prompt:
                    _state_for(resolved_id)["last_user"] = prompt

                # Always emit UserPromptSubmit so Island tracks the session turn,
                # even when the user message cannot be extracted.
                try:
                    _emit(
                        _bridge_payload(
                            resolved_id,
                            hook_event_name="UserPromptSubmit",
                            prompt=prompt or _state_for(resolved_id).get("last_user"),
                            cwd=cwd,
                        )
                    )
                except Exception:
                    pass
                return None


            def _on_pre_tool_call(tool_name=None, args=None, task_id=None, **kwargs):
                resolved_id = _resolve_session_id(task_id, kwargs.get("session_id"), **kwargs)
                if not resolved_id:
                    return
                payload = _bridge_payload(
                    resolved_id,
                    hook_event_name="PreToolUse",
                    tool_name=_stable_text(tool_name) or "Tool",
                    tool_use_id=_stable_text(kwargs.get("tool_call_id")),
                    cwd=_resolve_cwd(kwargs),
                )
                _emit(payload)
                return None


            def _on_post_tool_call(tool_name=None, args=None, result=None, task_id=None, **kwargs):
                resolved_id = _resolve_session_id(task_id, kwargs.get("session_id"), **kwargs)
                if not resolved_id:
                    return

                _, error_text = _parse_tool_result(result)
                payload = _bridge_payload(
                    resolved_id,
                    hook_event_name="PostToolUseFailure" if error_text else "PostToolUse",
                    tool_name=_stable_text(tool_name) or "Tool",
                    tool_use_id=_stable_text(kwargs.get("tool_call_id")),
                    error="Tool failed" if error_text else None,
                    cwd=_resolve_cwd(kwargs),
                )
                _emit(payload)
                return None


            def _on_post_llm_call(session_id=None, assistant_response=None, **kwargs):
                resolved_id = _resolve_session_id(session_id, kwargs.get("task_id"), **kwargs)
                if not resolved_id:
                    return
                reply = _stable_text(assistant_response) or _extract_assistant_message(kwargs)
                if reply:
                    _state_for(resolved_id)["last_assistant"] = reply
                    _emit(
                        _bridge_payload(
                            resolved_id,
                            hook_event_name="Notification",
                            notification_type="assistant_message",
                            message=reply,
                            platform=_stable_text(kwargs.get("platform")),
                            model=_stable_text(kwargs.get("model")),
                            cwd=_resolve_cwd(kwargs),
                        )
                    )
                return None


            def _on_session_end(session_id=None, completed=None, interrupted=None, platform=None, model=None, **kwargs):
                resolved_id = _resolve_session_id(session_id, kwargs.get("task_id"), **kwargs)
                if not resolved_id:
                    return

                state = _state_for(resolved_id)
                assistant = state.get("last_assistant") or _extract_assistant_message(kwargs)
                payload = _bridge_payload(
                    resolved_id,
                    hook_event_name="Stop",
                    last_assistant_message=assistant,
                    platform=_stable_text(platform),
                    model=_stable_text(model),
                    completed=bool(completed),
                    interrupted=bool(interrupted),
                    cwd=_resolve_cwd(kwargs),
                )
                _emit(payload)
                return None

            def _on_session_finalize(session_id=None, platform=None, model=None, **kwargs):
                resolved_id = _resolve_session_id(session_id, kwargs.get("task_id"), **kwargs)
                if not resolved_id:
                    return

                state = _state_for(resolved_id)
                assistant = state.get("last_assistant") or _extract_assistant_message(kwargs)
                payload = _bridge_payload(
                    resolved_id,
                    hook_event_name="SessionEnd",
                    last_assistant_message=assistant,
                    platform=_stable_text(platform),
                    model=_stable_text(model),
                    completed=True,
                    interrupted=False,
                    cwd=_resolve_cwd(kwargs),
                )
                _emit(payload)
                _SESSION_STATE.pop(resolved_id, None)
                return None


            def _on_session_reset(session_id=None, platform=None, model=None, **kwargs):
                resolved_id = _resolve_session_id(session_id, kwargs.get("task_id"), **kwargs)
                if not resolved_id:
                    return
                _emit_session_start(
                    resolved_id,
                    platform=platform,
                    model=model,
                    message=_extract_user_message(kwargs),
                    cwd=_resolve_cwd(kwargs),
                )
                return None


            def _on_subagent_start(parent_session_id=None, child_session_id=None, child_role=None, **kwargs):
                resolved_id = _resolve_session_id(parent_session_id, **kwargs)
                if not resolved_id:
                    return None
                _emit(
                    _bridge_payload(
                        resolved_id,
                        hook_event_name="SubagentStart",
                        agent_id=_stable_text(child_session_id) or _stable_text(kwargs.get("child_subagent_id")),
                        message=_stable_text(child_role) or "Subagent",
                    )
                )
                return None


            def _on_subagent_stop(parent_session_id=None, child_status=None, child_role=None, **kwargs):
                resolved_id = _resolve_session_id(parent_session_id, **kwargs)
                if not resolved_id:
                    return None
                _emit(
                    _bridge_payload(
                        resolved_id,
                        hook_event_name="SubagentStop",
                        agent_id=_stable_text(kwargs.get("child_session_id")) or _stable_text(kwargs.get("child_subagent_id")),
                        message=_stable_text(child_role) or _stable_text(child_status) or "Subagent",
                    )
                )
                return None


            def _on_pre_approval_request(session_key=None, surface=None, description=None, pattern_key=None, **kwargs):
                if _stable_text(surface) not in ("cli", "desktop"):
                    return None
                resolved_id = _resolve_session_id(session_key, **kwargs)
                if not resolved_id:
                    return None
                state = _state_for(resolved_id)
                state["platform"] = _stable_text(surface)
                _emit(
                    _bridge_payload(
                        resolved_id,
                        hook_event_name="PermissionRequest",
                        tool_name="Approval",
                        tool_use_id=_stable_text(pattern_key),
                        message=_stable_text(description),
                    )
                )
                return None


            def _on_post_approval_response(session_key=None, surface=None, pattern_key=None, **kwargs):
                if _stable_text(surface) not in ("cli", "desktop"):
                    return None
                resolved_id = _resolve_session_id(session_key, **kwargs)
                if not resolved_id:
                    return None
                _emit(
                    _bridge_payload(
                        resolved_id,
                        hook_event_name="PostToolUse",
                        tool_name="Approval",
                        tool_use_id=_stable_text(pattern_key),
                    )
                )
                return None


            def register(ctx):
                ctx.register_hook("on_session_start", _on_session_start)
                ctx.register_hook("pre_llm_call", _on_pre_llm_call)
                ctx.register_hook("pre_tool_call", _on_pre_tool_call)
                ctx.register_hook("post_tool_call", _on_post_tool_call)
                ctx.register_hook("post_llm_call", _on_post_llm_call)
                ctx.register_hook("on_session_end", _on_session_end)
                ctx.register_hook("on_session_finalize", _on_session_finalize)
                ctx.register_hook("on_session_reset", _on_session_reset)
                ctx.register_hook("subagent_start", _on_subagent_start)
                ctx.register_hook("subagent_stop", _on_subagent_stop)
                ctx.register_hook("pre_approval_request", _on_pre_approval_request)
                ctx.register_hook("post_approval_response", _on_post_approval_response)
            """

        return [
            "plugin.yaml": pluginYAML,
            "__init__.py": initPy,
        ]
    }

    private static func managedAntigravityPluginFiles(
        for profile: ManagedHookClientProfile,
        bridgeArguments: [String]?,
        bridgeEnvironment: [String: String]
    ) -> [String: String] {
        let marker = managedMarker(for: profile)
        let resolvedBridgeArguments = bridgeArguments ?? bridgeCommandArguments(for: profile)
        let environmentPrefix =
            bridgeEnvironment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(shellQuoted($0.value))" }

        var eventHooks: [String: Any] = [:]
        for event in profile.events {
            let command =
                (environmentPrefix
                + (resolvedBridgeArguments + ["--event", event.name]).map(shellQuotedIfNeeded)).joined(separator: " ")
            eventHooks[event.name] = makeHookEntries(command: command, event: event)
        }

        let manifest: [String: Any] = [
            "$schema": "https://antigravity.google/schemas/v1/plugin.json",
            "name": "ping-island",
            "description": "\(marker). Forward Antigravity CLI activity to Ping Island.",
        ]
        let hooks: [String: Any] = ["ping-island": eventHooks]

        func jsonString(_ object: Any) -> String {
            guard
                let data = try? JSONSerialization.data(
                    withJSONObject: object,
                    options: [.prettyPrinted, .sortedKeys]
                )
            else {
                return "{}"
            }
            return String(data: data, encoding: .utf8) ?? "{}"
        }

        return [
            "plugin.json": jsonString(manifest),
            "hooks.json": jsonString(hooks),
        ]
    }

    private static func managedPiExtensionSource(for profile: ManagedHookClientProfile) -> String {
        let argsData =
            (try? JSONSerialization.data(withJSONObject: bridgeCommandArguments(for: profile), options: []))
            ?? Data("[]".utf8)
        let argsJSON = String(data: argsData, encoding: .utf8) ?? "[]"
        let marker = managedMarker(for: profile)

        return """
            // \(marker)
            // Generated by Ping Island. Reinstall from Island settings if you need to refresh it.

            import { spawn, execFileSync } from "node:child_process";
            import type { AssistantMessage } from "@earendil-works/pi-ai";
            import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

            const BRIDGE_ARGS = \(argsJSON);
            const ENV_KEYS = [
              "TERM_PROGRAM",
              "ITERM_SESSION_ID",
              "TERM_SESSION_ID",
              "TMUX",
              "TMUX_PANE",
              "KITTY_WINDOW_ID",
              "WEZTERM_PANE",
              "KAKU_PANE_ID",
              "ZELLIJ_PANE_ID",
              "ZELLIJ_SESSION_NAME",
              "CMUX_WORKSPACE_ID",
              "CMUX_SURFACE_ID",
              "CMUX_SOCKET_PATH",
              "__CFBundleIdentifier",
              "VSCODE_CWD",
              "VSCODE_IPC_HOOK_CLI",
              "CURSOR_TRACE_ID",
              "SSH_CONNECTION",
              "SSH_CLIENT",
              "SSH_TTY",
              "HOSTNAME",
            ];

            const DANGEROUS_BASH_PATTERNS = [
              /\\brm\\s+(-rf?|--recursive)/i,
              /\\bsudo\\b/i,
              /\\b(chmod|chown)\\b.*777/i,
            ];

            function isObject(value: unknown): value is Record<string, unknown> {
              return !!value && typeof value === "object" && !Array.isArray(value);
            }

            function collectEnv(): Record<string, string> {
              const env: Record<string, string> = {};
              for (const key of ENV_KEYS) {
                const value = process.env[key];
                if (typeof value === "string" && value.length > 0) {
                  env[key] = value;
                }
              }
              return env;
            }

            function detectTTY(): string | undefined {
              try {
                let pid = process.pid;
                for (let index = 0; index < 8; index += 1) {
                  const output = execFileSync("ps", ["-o", "tty=,ppid=", "-p", String(pid)], {
                    timeout: 1000,
                  }).toString().trim();
                  const [tty, ppid] = output.split(/\\s+/);
                  if (tty && tty !== "??" && tty !== "?") {
                    return tty.startsWith("/dev/") ? tty : `/dev/${tty}`;
                  }
                  const next = Number.parseInt(ppid ?? "0", 10);
                  if (!next || next <= 1) break;
                  pid = next;
                }
              } catch {
                return undefined;
              }
              return undefined;
            }

            function displayToolName(name: string): string {
              return name.charAt(0).toUpperCase() + name.slice(1);
            }

            function extractLastAssistantText(messages: readonly unknown[]): string | undefined {
              const assistants = messages.filter(
                (message): message is AssistantMessage =>
                  isObject(message) && message.role === "assistant",
              );
              const last = assistants.at(-1);
              if (!last || !Array.isArray(last.content)) return undefined;
              const text = last.content
                .filter((part): part is { type: "text"; text: string } =>
                  isObject(part) && part.type === "text" && typeof part.text === "string",
                )
                .map((part) => part.text)
                .join("")
                .trim();
              return text.length > 0 ? text : undefined;
            }

            function buildToolInput(event: { toolName: string; input: Record<string, unknown> }): Record<string, unknown> {
              const input: Record<string, unknown> = { ...event.input };
              if (event.toolName === "bash" && typeof input.command === "string") {
                input.patterns = [input.command];
              }
              if ((event.toolName === "edit" || event.toolName === "write") && typeof input.path === "string") {
                input.file_path = input.path;
              }
              return input;
            }

            function isDangerousBash(event: { toolName: string; input: Record<string, unknown> }): boolean {
              if (event.toolName !== "bash" || typeof event.input.command !== "string") return false;
              return DANGEROUS_BASH_PATTERNS.some((pattern) => pattern.test(event.input.command as string));
            }

            function basePayload(
              sessionId: string,
              cwd: string,
              tty: string | undefined,
              extra: Record<string, unknown>,
            ): Record<string, unknown> {
              return {
                session_id: `pi-${sessionId}`,
                cwd,
                _source: "claude",
                _ppid: process.pid,
                _env: collectEnv(),
                _tty: tty,
                ...extra,
              };
            }

            function runBridge(
              payload: Record<string, unknown>,
              captureResponse: boolean,
            ): Promise<Record<string, unknown> | null> {
              return new Promise((resolve) => {
                const [command, ...args] = BRIDGE_ARGS;
                if (typeof command !== "string" || command.length === 0) {
                  resolve(null);
                  return;
                }

                try {
                  const env = { ...process.env };
                  if (isObject(payload._env)) {
                    Object.assign(env, payload._env);
                  }
                  if (typeof payload._tty === "string" && payload._tty.length > 0) {
                    env.TTY = payload._tty;
                  }

                  const child = spawn(command, args, {
                    stdio: ["pipe", captureResponse ? "pipe" : "ignore", "ignore"],
                    env,
                  });
                  let stdout = "";
                  child.stdout?.setEncoding("utf8");
                  child.stdout?.on("data", (chunk) => {
                    stdout += chunk;
                  });
                  child.on("error", () => resolve(null));
                  child.on("close", (code) => {
                    if (!captureResponse || code !== 0 || stdout.trim().length === 0) {
                      resolve(null);
                      return;
                    }
                    try {
                      resolve(JSON.parse(stdout.trim()) as Record<string, unknown>);
                    } catch {
                      resolve(null);
                    }
                  });
                  child.stdin.end(JSON.stringify(payload));
                } catch {
                  resolve(null);
                }
              });
            }

            function deniedByIsland(response: Record<string, unknown> | null): boolean {
              const hookSpecificOutput = isObject(response?.hookSpecificOutput)
                ? response.hookSpecificOutput
                : undefined;
              const decision = isObject(hookSpecificOutput?.decision)
                ? hookSpecificOutput.decision
                : undefined;
              const behavior = typeof decision?.behavior === "string" ? decision.behavior : undefined;
              const permissionDecision = typeof hookSpecificOutput?.permissionDecision === "string"
                ? hookSpecificOutput.permissionDecision
                : undefined;
              return behavior === "deny" || permissionDecision === "deny";
            }

            export default function pingIslandPiExtension(pi: ExtensionAPI) {
              const tty = detectTTY();
              const pendingPermissionSessions = new Set<string>();

              pi.on("session_start", async (_event, ctx) => {
                const sessionId = ctx.sessionManager.getSessionId();
                const sessionName = pi.getSessionName();
                await runBridge(basePayload(sessionId, ctx.cwd, tty, {
                  hook_event_name: "SessionStart",
                  ...(sessionName ? { session_title: sessionName } : {}),
                }), false);
              });

              pi.on("session_shutdown", async (_event, ctx) => {
                const sessionId = ctx.sessionManager.getSessionId();
                await runBridge(basePayload(sessionId, ctx.cwd, tty, {
                  hook_event_name: "SessionEnd",
                }), false);
              });

              pi.on("before_agent_start", async (event, ctx) => {
                const sessionId = ctx.sessionManager.getSessionId();
                if (pendingPermissionSessions.has(`pi-${sessionId}`)) return;
                await runBridge(basePayload(sessionId, ctx.cwd, tty, {
                  hook_event_name: "UserPromptSubmit",
                  prompt: event.prompt ?? "",
                }), false);
              });

              pi.on("tool_call", async (event, ctx) => {
                const sessionId = ctx.sessionManager.getSessionId();
                const bridgedSessionId = `pi-${sessionId}`;
                const toolName = displayToolName(event.toolName);
                const toolInput = buildToolInput(event);

                if (isDangerousBash(event)) {
                  pendingPermissionSessions.add(bridgedSessionId);
                  try {
                    const response = await runBridge(basePayload(sessionId, ctx.cwd, tty, {
                      hook_event_name: "PermissionRequest",
                      tool_name: toolName,
                      tool_input: toolInput,
                      _pi_tool_call_id: event.toolCallId,
                    }), true);
                    if (deniedByIsland(response)) {
                      return { block: true, reason: "Blocked by Ping Island" };
                    }
                  } finally {
                    pendingPermissionSessions.delete(bridgedSessionId);
                  }
                }

                await runBridge(basePayload(sessionId, ctx.cwd, tty, {
                  hook_event_name: "PreToolUse",
                  tool_name: toolName,
                  tool_input: toolInput,
                  _pi_tool_call_id: event.toolCallId,
                }), false);
                return undefined;
              });

              pi.on("tool_result", async (event, ctx) => {
                const sessionId = ctx.sessionManager.getSessionId();
                if (pendingPermissionSessions.has(`pi-${sessionId}`)) return;
                await runBridge(basePayload(sessionId, ctx.cwd, tty, {
                  hook_event_name: "PostToolUse",
                  tool_name: displayToolName(event.toolName),
                  tool_input: event.input,
                  is_error: event.isError,
                  _pi_tool_call_id: event.toolCallId,
                }), false);
              });

              pi.on("agent_end", async (event, ctx) => {
                const sessionId = ctx.sessionManager.getSessionId();
                if (pendingPermissionSessions.has(`pi-${sessionId}`)) return;
                const sessionName = pi.getSessionName();
                await runBridge(basePayload(sessionId, ctx.cwd, tty, {
                  hook_event_name: "Stop",
                  last_assistant_message: extractLastAssistantText(event.messages),
                  ...(sessionName ? { session_title: sessionName } : {}),
                }), false);
              });

              pi.on("session_before_compact", async (_event, ctx) => {
                const sessionId = ctx.sessionManager.getSessionId();
                await runBridge(basePayload(sessionId, ctx.cwd, tty, {
                  hook_event_name: "PreCompact",
                }), false);
              });

              pi.on("session_compact", async (_event, ctx) => {
                const sessionId = ctx.sessionManager.getSessionId();
                await runBridge(basePayload(sessionId, ctx.cwd, tty, {
                  hook_event_name: "PostCompact",
                }), false);
              });
            }
            """
    }

    static func managedHookDirectoryFiles(
        for profile: ManagedHookClientProfile,
        bridgeArguments: [String]? = nil,
        bridgeEnvironment: [String: String] = [:]
    ) -> [String: String] {
        guard profile.id == "openclaw-hooks" else {
            return [:]
        }

        let resolvedBridgeArguments = bridgeArguments ?? bridgeCommandArguments(for: profile)
        let argsData =
            (try? JSONSerialization.data(withJSONObject: resolvedBridgeArguments, options: []))
            ?? Data("[]".utf8)
        let argsJSON = String(data: argsData, encoding: .utf8) ?? "[]"
        let environmentData =
            (try? JSONSerialization.data(withJSONObject: bridgeEnvironment, options: [.sortedKeys]))
            ?? Data("{}".utf8)
        let environmentJSON = String(data: environmentData, encoding: .utf8) ?? "{}"
        let eventList = ["command", "message", "session"]
        let eventsData =
            (try? JSONSerialization.data(withJSONObject: eventList, options: []))
            ?? Data("[]".utf8)
        let eventsJSON = String(data: eventsData, encoding: .utf8) ?? "[]"
        let marker = managedMarker(for: profile)
        let hookName = profile.activationEntryName ?? profile.primaryConfigurationURL.lastPathComponent

        let hookMD = """
            ---
            name: \(hookName)
            description: "Forward OpenClaw internal hook events to Ping Island"
            metadata:
              { "openclaw": { "events": \(eventsJSON) } }
            ---

            <!-- \(marker) -->

            # Ping Island OpenClaw Hook

            Generated by Ping Island. Reinstall from Island settings if you need to refresh it.
            """

        let handlerTS = """
            // \(marker)
            // Generated by Ping Island. Reinstall from Island settings if you need to refresh it.

            const BRIDGE_ARGS = \(argsJSON);
            const BRIDGE_ENV = \(environmentJSON);

            function stableString(value) {
              if (value == null) return undefined;
              if (typeof value === "string") {
                const trimmed = value.trim();
                return trimmed.length > 0 ? trimmed : undefined;
              }
              try {
                return JSON.stringify(value);
              } catch {
                return undefined;
              }
            }

            function firstDefined(...values) {
              for (const value of values) {
                if (value !== undefined && value !== null && value !== "") {
                  return value;
                }
              }
              return undefined;
            }

            function summarizeContent(content) {
              if (typeof content === "string") return content;
              if (Array.isArray(content)) {
                const parts = content
                  .map((entry) => summarizeContent(entry))
                  .filter(Boolean);
                return parts.length > 0 ? parts.join("\\n") : undefined;
              }
              if (content && typeof content === "object") {
                return firstDefined(
                  summarizeContent(content.text),
                  summarizeContent(content.body),
                  summarizeContent(content.message),
                  stableString(content)
                );
              }
              return undefined;
            }

            function statusFor(event) {
              const key = `${event?.type ?? ""}:${event?.action ?? ""}`;
              switch (key) {
                case "command:new":
                case "command:reset":
                case "message:received":
                  return "thinking";
                case "message:sent":
                  return "waitingForInput";
                case "command:stop":
                  return "completed";
                case "session:compact:before":
                  return "compacting";
                case "session:compact:after":
                case "session:patch":
                  return "active";
                default:
                  return "active";
              }
            }

            function titleFor(event) {
              return firstDefined(
                event?.context?.sessionEntry?.title,
                event?.context?.sessionEntry?.name,
                event?.context?.patch?.title,
                "OpenClaw"
              );
            }

            function previewFor(event) {
              return firstDefined(
                summarizeContent(event?.context?.content),
                summarizeContent(event?.context?.bodyForAgent),
                summarizeContent(event?.context?.transcript),
                summarizeContent(event?.context?.patch),
                event?.context?.commandSource,
                `${event?.type ?? "event"}:${event?.action ?? "unknown"}`
              );
            }

            function buildPayload(event) {
              const rawSessionId = firstDefined(
                event?.context?.sessionEntry?.id,
                event?.context?.sessionEntry?.sessionID,
                event?.context?.sessionEntry?.sessionId,
                event?.context?.patch?.sessionID,
                event?.context?.patch?.sessionId,
                event?.sessionKey,
                event?.sessionID,
                event?.sessionId,
                event?.context?.sessionKey,
                event?.context?.sessionID,
                event?.context?.sessionId
              );
              const sessionId = stableString(rawSessionId);
              if (!sessionId) {
                return {
                  payload: undefined,
                  skipReason: "missing_session_id",
                  rawSessionId: stableString(rawSessionId)
                };
              }

              const payload = {
                event: `${event?.type ?? "unknown"}:${event?.action ?? "unknown"}`,
                session_id: sessionId,
                session_file_path: `${process.env.HOME ?? ""}/.openclaw/agents/main/sessions/${sessionId}.jsonl`,
                cwd: firstDefined(
                  event?.context?.workspaceDir,
                  event?.context?.workspace?.dir,
                  event?.context?.directory,
                  event?.context?.sessionEntry?.workspaceDir,
                  event?.context?.sessionEntry?.directory,
                  event?.context?.cfg?.workspace?.dir
                ),
                status: statusFor(event),
                title: titleFor(event),
                message: previewFor(event),
                client_kind: "openclaw",
                client_name: "OpenClaw",
                client_origin: "gateway",
                client_originator: "OpenClaw",
                thread_source: "openclaw-hooks"
              };

              return {
                payload: Object.fromEntries(
                  Object.entries(payload).filter(([, value]) => value !== undefined && value !== null && value !== "")
                ),
                skipReason: undefined,
                rawSessionId: stableString(rawSessionId)
              };
            }

            async function forwardViaNode(payload) {
              const { spawn } = await import("node:child_process");
              const env = { ...(process?.env ?? {}), ...BRIDGE_ENV };
              return await new Promise((resolve, reject) => {
                const child = spawn(BRIDGE_ARGS[0], BRIDGE_ARGS.slice(1), {
                  stdio: ["pipe", "ignore", "ignore"],
                  env
                });
                child.once("error", reject);
                child.once("close", (code, signal) => {
                  resolve({ code, signal });
                });
                child.stdin.on("error", () => {});
                child.stdin.write(JSON.stringify(payload));
                child.stdin.end();
              });
            }

            const handler = async (event) => {
              const { payload } = buildPayload(event);
              if (!payload) return;

              try {
                const env = { ...(globalThis.process?.env ?? {}), ...BRIDGE_ENV };
                if (typeof Bun !== "undefined" && typeof Bun.spawn === "function") {
                  const subprocess = Bun.spawn(BRIDGE_ARGS, {
                    stdin: new Response(JSON.stringify(payload)),
                    stdout: "ignore",
                    stderr: "ignore",
                    env
                  });
                  void subprocess.exited.catch(() => {});
                  return;
                }

                await forwardViaNode(payload);
              } catch {
                // OpenClaw hooks should never fail because Ping Island is unavailable.
              }
            };

            export default handler;
            """

        return [
            "HOOK.md": hookMD,
            "handler.ts": handlerTS,
        ]
    }

    // MARK: - Custom Hook Installations

    private static let customInstallationsDefaultsKey = "HookInstaller.customInstallations.v1"

    struct CustomHookInstallation: Codable, Identifiable, Equatable {
        let id: String
        let profileID: String
        let customPath: String
        let installedAt: Date

        var customURL: URL {
            URL(fileURLWithPath: customPath)
        }

        var profileTitle: String {
            ClientProfileRegistry.managedHookProfile(id: profileID)?.title ?? profileID
        }
    }

    static func customInstallations() -> [CustomHookInstallation] {
        guard let data = UserDefaults.standard.data(forKey: customInstallationsDefaultsKey),
            let installations = try? JSONDecoder().decode([CustomHookInstallation].self, from: data)
        else {
            return []
        }
        return installations
    }

    static func installCustom(profileID: String, directoryPath: String) {
        guard let profile = ClientProfileRegistry.managedHookProfile(id: profileID) else {
            return
        }

        let directoryURL = URL(fileURLWithPath: directoryPath)
        let url = customInstallationURL(for: profile, baseDirectory: directoryURL)
        let activationConfigURL = customActivationConfigurationURL(for: profile, baseDirectory: directoryURL)

        installBridgeLauncherIfNeeded()
        switch profile.installationKind {
        case .jsonHooks:
            updateHooks(at: url, profile: profile)
        case .pluginFile:
            writeManagedPlugin(at: url, profile: profile)
            setManagedPluginEnabled(true, for: profile, customConfigURL: activationConfigURL, pluginURL: url)
        case .pluginDirectory:
            writeManagedPluginDirectory(at: url, profile: profile)
            if profile.id == "dsh-hooks" {
                setManagedDSHPluginEnabled(
                    true,
                    for: profile,
                    customConfigURL: activationConfigURL,
                    pluginURL: url
                )
            }
        case .hookDirectory:
            writeManagedHookDirectory(at: url, profile: profile)
            setInternalHookEnabled(true, for: profile, customConfigURL: activationConfigURL)
        case .tomlHooks:
            updateTOMLHooks(at: url, profile: profile)
        }

        let installation = CustomHookInstallation(
            id: UUID().uuidString,
            profileID: profileID,
            customPath: url.path,
            installedAt: Date()
        )
        var existing = customInstallations()
        existing.append(installation)
        persistCustomInstallations(existing)
    }

    static func uninstallCustom(id: String) {
        var installations = customInstallations()
        guard let index = installations.firstIndex(where: { $0.id == id }) else {
            return
        }

        let installation = installations[index]
        let url = installation.customURL

        if let profile = ClientProfileRegistry.managedHookProfile(id: installation.profileID) {
            let activationConfigURL = customActivationConfigurationURL(for: profile, installedURL: url)
            switch profile.installationKind {
            case .jsonHooks:
                removeManagedHooks(at: url)
            case .pluginFile:
                removeManagedPlugin(at: url, profile: profile)
                setManagedPluginEnabled(false, for: profile, customConfigURL: activationConfigURL, pluginURL: url)
            case .pluginDirectory:
                if profile.id == "dsh-hooks" {
                    setManagedDSHPluginEnabled(
                        false,
                        for: profile,
                        customConfigURL: activationConfigURL,
                        pluginURL: url
                    )
                }
                removeManagedPluginDirectory(at: url, profile: profile)
            case .hookDirectory:
                removeManagedHookDirectory(at: url, profile: profile)
                setInternalHookEnabled(false, for: profile, customConfigURL: activationConfigURL)
            case .tomlHooks:
                removeManagedTOMLHooks(at: url)
            }
        }

        installations.remove(at: index)
        persistCustomInstallations(installations)
    }

    static func isCustomInstalled(_ installation: CustomHookInstallation) -> Bool {
        guard let profile = ClientProfileRegistry.managedHookProfile(id: installation.profileID) else {
            return false
        }
        let url = installation.customURL
        switch profile.installationKind {
        case .jsonHooks:
            return containsManagedHooks(at: url)
        case .pluginFile:
            return containsManagedPlugin(at: url, profile: profile)
        case .pluginDirectory:
            let containsDirectory = containsManagedPluginDirectory(at: url, profile: profile)
            guard profile.id == "dsh-hooks" else { return containsDirectory }
            let activationConfigURL = customActivationConfigurationURL(for: profile, installedURL: url)
            guard let activationConfigURL,
                let content = try? String(contentsOf: activationConfigURL, encoding: .utf8)
            else {
                return false
            }
            return containsDirectory
                && containsManagedDSHPatch(
                    content,
                    pluginURL: dshPluginEntryURL(for: url)
                )
        case .hookDirectory:
            let activationConfigURL = customActivationConfigurationURL(for: profile, installedURL: url)
            return containsManagedHookDirectory(at: url, profile: profile)
                && isInternalHookEnabled(at: activationConfigURL, for: profile)
        case .tomlHooks:
            return containsManagedTOMLHooks(at: url)
        }
    }

    private static func persistCustomInstallations(_ installations: [CustomHookInstallation]) {
        guard let data = try? JSONEncoder().encode(installations) else {
            return
        }
        UserDefaults.standard.set(data, forKey: customInstallationsDefaultsKey)
    }

    // MARK: - JSON Utilities

    nonisolated static func remoteBridgeBinaryURL() -> URL? {
        preferredBridgeBinaryURL()
    }

    nonisolated static func managedBridgeCommand(
        source: String,
        extraArguments: [String],
        launcherPath: String,
        socketPath: String?
    ) -> String {
        var components: [String] = []
        if let socketPath, !socketPath.isEmpty {
            components.append("ISLAND_SOCKET_PATH=\(shellQuoted(socketPath))")
        }
        components.append(shellQuoted(launcherPath))
        components.append("--source")
        components.append(source)
        components.append(contentsOf: extraArguments.map(shellQuoted))
        return components.joined(separator: " ")
    }

    nonisolated static func updatedInternalHookConfigurationData(
        existingData: Data?,
        entryName: String,
        installing: Bool
    ) -> Data {
        var json: [String: Any] = [:]
        if let existingData,
            let existing = HookConfigParser.parseJSONObject(from: existingData)
        {
            json = existing
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        var internalHooks = hooks["internal"] as? [String: Any] ?? [:]
        var entries = internalHooks["entries"] as? [String: Any] ?? [:]
        var entry = entries[entryName] as? [String: Any] ?? [:]

        entry["enabled"] = installing
        entries[entryName] = entry

        if installing {
            internalHooks["enabled"] = true
        }

        internalHooks["entries"] = entries
        hooks["internal"] = internalHooks
        json["hooks"] = hooks

        return
            (try? JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys]
            )) ?? Data("{}".utf8)
    }

    nonisolated static func isInternalHookEnabled(
        existingData: Data?,
        entryName: String
    ) -> Bool {
        guard let existingData,
            let json = HookConfigParser.parseJSONObject(from: existingData),
            let hooks = json["hooks"] as? [String: Any],
            let internalHooks = hooks["internal"] as? [String: Any],
            let entries = internalHooks["entries"] as? [String: Any],
            let entry = entries[entryName] as? [String: Any],
            let enabled = entry["enabled"] as? Bool
        else {
            return false
        }

        return enabled
    }

    nonisolated static func updatedConfigurationData(
        existingData: Data?,
        profile: ManagedHookClientProfile,
        customCommand: String,
        installing: Bool,
        removingCommandPrefixes: [String] = [],
        pluginURL: URL? = nil
    ) -> Data {
        var json: [String: Any] = [:]
        if let existingData,
            let existing = HookConfigParser.parseJSONObject(from: existingData)
        {
            json = existing
        }

        switch profile.installationKind {
        case .jsonHooks:
            var hooks = json["hooks"] as? [String: Any] ?? [:]
            if installing {
                hooks = removingIslandManagedHooks(from: hooks, profile: profile)
                let preferredFirst =
                    profile.id == "qoder-cli-hooks"
                    || profile.id == "qoder-cn-cli-hooks"
                    || profile.id == "codebuddy-cli-hooks"
                for event in profile.events {
                    let existingEvent = sanitizedHookEntries(
                        hooks[event.name] as? [[String: Any]],
                        removingCommandPrefixes: removingCommandPrefixes
                    )
                    hooks[event.name] = normalizedHookEntries(
                        existingEvent,
                        preferred: makeHookEntries(command: customCommand, event: event),
                        preferredFirst: preferredFirst,
                        profile: profile
                    )
                }
            } else {
                for (event, value) in hooks {
                    guard var entries = value as? [[String: Any]] else { continue }
                    entries.removeAll { entry in
                        isIslandManagedHookEntry(entry, for: profile)
                    }
                    if entries.isEmpty {
                        hooks.removeValue(forKey: event)
                    } else {
                        hooks[event] = entries
                    }
                }
            }

            if hooks.isEmpty {
                json.removeValue(forKey: "hooks")
            } else {
                json["hooks"] = hooks
            }

        case .pluginFile:
            let targetPluginURL = pluginURL ?? profile.primaryConfigurationURL
            let pluginSpecifier = targetPluginURL.absoluteURL.absoluteString
            let pluginPath = targetPluginURL.path
            let existingPlugins = json["plugin"] as? [Any] ?? []
            let filteredPlugins = existingPlugins.filter { entry in
                !pluginEntry(entry, matches: pluginSpecifier, pluginPath: pluginPath)
            }

            if installing {
                json["plugin"] = filteredPlugins + [pluginSpecifier]
            } else if filteredPlugins.isEmpty {
                json.removeValue(forKey: "plugin")
            } else {
                json["plugin"] = filteredPlugins
            }
        case .pluginDirectory, .hookDirectory:
            break
        case .tomlHooks:
            break
        }

        let data =
            (try? JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys]
            )) ?? Data("{}".utf8)
        return data
    }

    private nonisolated static func sanitizedHookEntries(
        _ entries: [[String: Any]]?,
        removingCommandPrefixes: [String]
    ) -> [[String: Any]]? {
        guard !removingCommandPrefixes.isEmpty else { return entries }
        return entries?.filter { entry in
            !entryContainsCommand(entry, withPrefixes: removingCommandPrefixes)
        }
    }

    private nonisolated static func entryContainsCommand(
        _ entry: [String: Any],
        withPrefixes prefixes: [String]
    ) -> Bool {
        if let command = hookCommandString(from: entry) {
            return prefixes.contains { command.hasPrefix($0) }
        }

        if let nestedHooks = entry["hooks"] as? [[String: Any]] {
            return nestedHooks.contains { hook in
                guard let command = hookCommandString(from: hook) else { return false }
                return prefixes.contains { command.hasPrefix($0) }
            }
        }

        return false
    }

    private static func writeJSONObject(_ json: [String: Any], to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func writeData(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func customInstallationURL(for profile: ManagedHookClientProfile, baseDirectory: URL) -> URL {
        switch profile.installationKind {
        case .jsonHooks, .pluginFile:
            return baseDirectory.appendingPathComponent(profile.primaryConfigurationURL.lastPathComponent)
        case .tomlHooks:
            return baseDirectory.appendingPathComponent(profile.primaryConfigurationURL.lastPathComponent)
        case .pluginDirectory:
            if profile.id == "dsh-hooks" {
                if baseDirectory.lastPathComponent == ".dsh" {
                    return
                        baseDirectory
                        .appendingPathComponent("plugins", isDirectory: true)
                        .appendingPathComponent(profile.primaryConfigurationURL.lastPathComponent, isDirectory: true)
                }
                if baseDirectory.lastPathComponent == "plugins" {
                    return baseDirectory.appendingPathComponent(
                        profile.primaryConfigurationURL.lastPathComponent,
                        isDirectory: true
                    )
                }
            }
            if profile.id == "antigravity-hooks" {
                if baseDirectory.lastPathComponent == "antigravity-cli" {
                    return
                        baseDirectory
                        .appendingPathComponent("plugins", isDirectory: true)
                        .appendingPathComponent(
                            profile.primaryConfigurationURL.lastPathComponent,
                            isDirectory: true
                        )
                }
                if baseDirectory.lastPathComponent == "plugins" {
                    return baseDirectory.appendingPathComponent(
                        profile.primaryConfigurationURL.lastPathComponent,
                        isDirectory: true
                    )
                }
            }
            if baseDirectory.lastPathComponent == ".hermes" {
                return
                    baseDirectory
                    .appendingPathComponent("plugins", isDirectory: true)
                    .appendingPathComponent(profile.primaryConfigurationURL.lastPathComponent, isDirectory: true)
            }
            if baseDirectory.lastPathComponent == "plugins" {
                return baseDirectory.appendingPathComponent(
                    profile.primaryConfigurationURL.lastPathComponent, isDirectory: true)
            }
            return baseDirectory.appendingPathComponent(
                profile.primaryConfigurationURL.lastPathComponent, isDirectory: true)
        case .hookDirectory:
            let selectedName = baseDirectory.lastPathComponent
            if selectedName == ".openclaw"
                || FileManager.default.fileExists(atPath: baseDirectory.appendingPathComponent("openclaw.json").path)
            {
                return
                    baseDirectory
                    .appendingPathComponent("hooks", isDirectory: true)
                    .appendingPathComponent(profile.primaryConfigurationURL.lastPathComponent, isDirectory: true)
            }
            if selectedName == "hooks" {
                return baseDirectory.appendingPathComponent(
                    profile.primaryConfigurationURL.lastPathComponent, isDirectory: true)
            }
            return baseDirectory.appendingPathComponent(
                profile.primaryConfigurationURL.lastPathComponent, isDirectory: true)
        }
    }

    private static func customActivationConfigurationURL(for profile: ManagedHookClientProfile, baseDirectory: URL)
        -> URL?
    {
        if profile.id == "dsh-hooks" {
            if baseDirectory.lastPathComponent == ".dsh" {
                return baseDirectory.appendingPathComponent("cordis.patch.yml")
            }
            if baseDirectory.lastPathComponent == "plugins" {
                return baseDirectory.deletingLastPathComponent().appendingPathComponent("cordis.patch.yml")
            }
            return profile.activationConfigurationURL
        }
        switch profile.installationKind {
        case .pluginFile:
            if baseDirectory.lastPathComponent == "plugins" {
                return baseDirectory.deletingLastPathComponent().appendingPathComponent("opencode.json")
            }
            return baseDirectory.appendingPathComponent("opencode.json")
        case .jsonHooks, .pluginDirectory, .tomlHooks:
            return nil
        case .hookDirectory:
            break
        }

        let selectedName = baseDirectory.lastPathComponent
        if selectedName == ".openclaw"
            || FileManager.default.fileExists(atPath: baseDirectory.appendingPathComponent("openclaw.json").path)
        {
            return baseDirectory.appendingPathComponent("openclaw.json")
        }
        if selectedName == "hooks" {
            return baseDirectory.deletingLastPathComponent().appendingPathComponent("openclaw.json")
        }
        return profile.activationConfigurationURL
    }

    private static func customActivationConfigurationURL(for profile: ManagedHookClientProfile, installedURL: URL)
        -> URL?
    {
        if profile.id == "dsh-hooks" {
            let pluginsDirectory = installedURL.deletingLastPathComponent()
            return pluginsDirectory.deletingLastPathComponent().appendingPathComponent("cordis.patch.yml")
        }
        switch profile.installationKind {
        case .pluginFile:
            return installedURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
                "opencode.json")
        case .jsonHooks, .pluginDirectory, .tomlHooks:
            return nil
        case .hookDirectory:
            break
        }
        let parent = installedURL.deletingLastPathComponent()
        if parent.lastPathComponent == "hooks" {
            return parent.deletingLastPathComponent().appendingPathComponent("openclaw.json")
        }
        return profile.activationConfigurationURL
    }

    private static func isInternalHookEnabled(at url: URL?, for profile: ManagedHookClientProfile) -> Bool {
        guard let url,
            let entryName = profile.activationEntryName,
            let data = try? Data(contentsOf: url)
        else {
            return false
        }
        return isInternalHookEnabled(existingData: data, entryName: entryName)
    }

    private nonisolated static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private nonisolated static func shellQuotedIfNeeded(_ string: String) -> String {
        let safeCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-=.,/:@%")
        if string.rangeOfCharacter(from: safeCharacters.inverted) == nil {
            return string
        }
        return shellQuoted(string)
    }

    nonisolated static func isManagedPluginEnabled(existingData: Data?, pluginURL: URL) -> Bool {
        guard let existingData,
            let json = HookConfigParser.parseJSONObject(from: existingData),
            let plugins = json["plugin"] as? [Any]
        else {
            return false
        }

        let pluginSpecifier = pluginURL.absoluteURL.absoluteString
        let pluginPath = pluginURL.path
        return plugins.contains { pluginEntry($0, matches: pluginSpecifier, pluginPath: pluginPath) }
    }

    private nonisolated static func pluginEntry(_ entry: Any, matches pluginSpecifier: String, pluginPath: String)
        -> Bool
    {
        if let string = entry as? String {
            return normalizedPluginLocation(string) == normalizedPluginLocation(pluginSpecifier)
                || normalizedPluginLocation(string) == normalizedPluginLocation(pluginPath)
        }

        if let pair = entry as? [Any],
            let string = pair.first as? String
        {
            return normalizedPluginLocation(string) == normalizedPluginLocation(pluginSpecifier)
                || normalizedPluginLocation(string) == normalizedPluginLocation(pluginPath)
        }

        return false
    }

    private nonisolated static func normalizedPluginLocation(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.isFileURL {
            return url.standardizedFileURL.path
        }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }
}
