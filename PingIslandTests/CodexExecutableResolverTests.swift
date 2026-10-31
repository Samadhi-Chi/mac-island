import Foundation
import XCTest

@testable import Ping_Island

final class CodexExecutableResolverTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testCurrentRenamedDesktopIsFoundWithoutCLIOnFinderPath() throws {
        let app = try application("Renamed Desktop.app")
        let cli = try executable(app, "Contents/Resources/codex-cli/bin/codex")
        XCTAssertEqual(resolve(preferred: [app]), cli.path)
    }

    func testNestedCLIBundleWorksWithoutWrapper() throws {
        let app = try application("Desktop.app")
        let cli = try executable(app, "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        XCTAssertEqual(resolve(preferred: [app]), cli.path)
    }

    func testLegacyDesktopLayoutRemainsSupported() throws {
        let app = try application("Codex.app")
        let cli = try executable(app, "Contents/Resources/codex")
        XCTAssertEqual(resolve(preferred: [app]), cli.path)
    }

    func testRunningApplicationPrecedesAnotherInstalledVersionAndPATH() throws {
        let current = try application("Running.app")
        let currentCLI = try executable(current, "Contents/Resources/codex-cli/bin/codex")
        let older = try application("Older.app")
        _ = try executable(older, "Contents/Resources/codex")
        let standalone = try executable(root, "bin/codex")
        XCTAssertEqual(
            resolve(preferred: [current, older], path: standalone.deletingLastPathComponent().path), currentCLI.path)
    }

    func testApplicationDirectoryFallbackFindsNestedUserInstall() throws {
        let app = try application("Applications/Tools/Renamed.app")
        let cli = try executable(app, "Contents/Resources/codex-cli/bin/codex")
        let found = try XCTUnwrap(resolve(directories: [root.appendingPathComponent("Applications")]))
        // Directory enumeration may expose /private/var while Foundation's
        // temporary URL uses /var. Compare the file reached by either alias.
        XCTAssertEqual(URL(fileURLWithPath: found).resolvingSymlinksInPath(), cli.resolvingSymlinksInPath())
    }

    func testUnrelatedApplicationWithCodexResourceIsIgnored() throws {
        let app = try application("Other.app", identifier: "example.other")
        _ = try executable(app, "Contents/Resources/codex-cli/bin/codex")
        XCTAssertNil(resolve(preferred: [app], directories: [root]))
    }

    func testNonExecutableWrapperFallsBackToLegacyFile() throws {
        let app = try application("Desktop.app")
        _ = try executable(app, "Contents/Resources/codex-cli/bin/codex", permissions: 0o600)
        let legacy = try executable(app, "Contents/Resources/codex")
        XCTAssertEqual(resolve(preferred: [app]), legacy.path)
    }

    func testExecutableDirectoryIsSkippedAndStandaloneCLIRemainsAvailable() throws {
        let app = try application("Desktop.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex"),
            withIntermediateDirectories: true
        )
        let cli = try executable(root, "bin/codex")
        XCTAssertEqual(resolve(preferred: [app], path: cli.deletingLastPathComponent().path), cli.path)
    }

    func testMissingExecutableReturnsUnavailableWithoutLaunchingAnything() throws {
        let app = try application("Desktop.app")
        XCTAssertNil(resolve(preferred: [app], directories: [root]))
    }

    private func resolve(preferred: [URL] = [], directories: [URL] = [], path: String? = nil) -> String? {
        CodexExecutableResolver.resolve(
            preferredApplications: preferred, applicationDirectories: directories,
            searchPath: path ?? root.appendingPathComponent("empty-bin").path
        )
    }

    private func application(_ name: String, identifier: String = "com.openai.codex") throws -> URL {
        let app = root.appendingPathComponent(name)
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL"],
            format: .xml, options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    private func executable(_ directory: URL, _ relativePath: String, permissions: Int = 0o700) throws -> URL {
        let file = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path)
        return file
    }
}
