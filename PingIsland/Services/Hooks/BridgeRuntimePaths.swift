import Foundation

enum BridgeRuntimePaths {
    #if APP_STORE
        nonisolated static let appGroupIdentifier = "group.com.wudanwu.PingIsland"
    #else
        nonisolated static var appGroupIdentifier: String {
            "group.\(MacIslandProductPolicy.runtimeBundleIdentifier)"
        }
    #endif
    nonisolated static let bridgeConfigEnvironmentKey = "MAC_ISLAND_BRIDGE_CONFIG"
    nonisolated static let socketPathEnvironmentKey = "MAC_ISLAND_SOCKET_PATH"

    nonisolated private static let configRelativePath = ".mac-island/bridge-config.json"

    nonisolated static var socketPath: String {
        #if APP_STORE
            runtimeDirectoryURL.appendingPathComponent("i.sock").path
        #else
            runtimeDirectoryURL
                .appendingPathComponent("run", isDirectory: true)
                .appendingPathComponent("mac-island.sock")
                .path
        #endif
    }

    nonisolated static var runtimeConfigURL: URL {
        #if APP_STORE
            runtimeDirectoryURL.appendingPathComponent("c.json")
        #else
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(configRelativePath)
        #endif
    }

    nonisolated static var runtimeDirectoryURL: URL {
        #if APP_STORE
            if let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            ) {
                return containerURL.appendingPathComponent("b", isDirectory: true)
            }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mac-island", isDirectory: true)
    }

    nonisolated static func prepareRuntimeDirectory() {
        try? FileManager.default.createDirectory(
            at: runtimeDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: runtimeDirectoryURL.path
        )
        try? FileManager.default.createDirectory(
            at: runtimeDirectoryURL.appendingPathComponent("run", isDirectory: true),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: runtimeDirectoryURL.appendingPathComponent("run", isDirectory: true).path
        )
    }

    nonisolated static var launcherEnvironment: [String: String] {
        [
            socketPathEnvironmentKey: socketPath,
            bridgeConfigEnvironmentKey: runtimeConfigURL.path,
        ]
    }
}
