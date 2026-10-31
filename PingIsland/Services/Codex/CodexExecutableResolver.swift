import AppKit
import Foundation

/// Resolve the desktop installation by identity, not its visible app name.
/// Finder-launched apps usually have no user-installed CLI on PATH.
nonisolated enum CodexExecutableResolver {
    static let bundleIdentifier = "com.openai.codex"

    @MainActor
    static func preferredApplications() -> [URL] {
        var applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .compactMap(\.bundleURL)
        if let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            applications.append(installed)
        }
        return applications
    }

    static func resolve(
        preferredApplications: [URL],
        applicationDirectories: [URL],
        searchPath: String,
        fileManager: FileManager = .default
    ) -> String? {
        let relativePaths = [
            "Contents/Resources/codex-cli/bin/codex",
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "Contents/Resources/codex",
        ]
        var visited = Set<String>()

        func executable(in application: URL) -> String? {
            guard visited.insert(application.standardizedFileURL.path).inserted,
                Bundle(url: application)?.bundleIdentifier == bundleIdentifier
            else { return nil }
            return relativePaths.lazy.map { application.appendingPathComponent($0).path }
                .first(where: isExecutable)
        }

        func isExecutable(_ path: String) -> Bool {
            guard fileManager.isExecutableFile(atPath: path),
                let values = try? URL(fileURLWithPath: path).resolvingSymlinksInPath()
                    .resourceValues(forKeys: [.isRegularFileKey])
            else { return false }
            return values.isRegularFile == true
        }

        for application in preferredApplications {
            if let path = executable(in: application) { return path }
        }
        for directory in applicationDirectories {
            guard
                let enumerator = fileManager.enumerator(
                    at: directory, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
            else { continue }
            for case let application as URL in enumerator where application.pathExtension == "app" {
                enumerator.skipDescendants()
                if let path = executable(in: application) { return path }
            }
        }
        return searchPath.split(separator: ":").filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex").path }
            .first(where: isExecutable)
    }
}
