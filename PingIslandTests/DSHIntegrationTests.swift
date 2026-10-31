import XCTest

@testable import Ping_Island

final class DSHIntegrationTests: XCTestCase {
    func testManagedProfileUsesOfficialDSHPluginLayer() throws {
        let profile = try XCTUnwrap(ClientProfileRegistry.managedHookProfile(id: "dsh-hooks"))

        XCTAssertEqual(profile.title, "DeepSeek Harness")
        XCTAssertEqual(profile.installationKind, .pluginDirectory)
        XCTAssertEqual(profile.primaryConfigurationURL.path, NSHomeDirectory() + "/.dsh/plugins/mac-island")
        XCTAssertEqual(profile.activationConfigurationURL?.path, NSHomeDirectory() + "/.dsh/cordis.patch.yml")
        XCTAssertEqual(profile.activationEntryName, "mac-island-observer")
        XCTAssertEqual(
            HookInstaller.dshPluginEntryURL(for: profile.primaryConfigurationURL).path,
            NSHomeDirectory() + "/.dsh/plugins/mac-island/index.mjs"
        )
        XCTAssertEqual(profile.bridgeSource, "claude")
        XCTAssertTrue(profile.bridgeExtraArguments.contains("dsh"))
        XCTAssertFalse(profile.defaultEnabled)
    }

    func testGeneratedPluginObservesOfficialEventsWithoutForwardingSensitiveToolData() throws {
        let profile = try XCTUnwrap(ClientProfileRegistry.managedHookProfile(id: "dsh-hooks"))
        let files = HookInstaller.managedPluginDirectoryFiles(for: profile)
        let source = try XCTUnwrap(files["index.mjs"])

        XCTAssertTrue(source.contains("export function apply(ctx)"))
        XCTAssertTrue(source.contains("ctx.on(\"agent/created\""))
        XCTAssertTrue(source.contains("ctx.on(\"agent/status\""))
        XCTAssertTrue(source.contains("ctx.on(\"agent/error\""))
        XCTAssertTrue(source.contains("ctx.on(\"session/event\", handleSessionEvent)"))
        XCTAssertTrue(source.contains("type === \"user/message\""))
        XCTAssertTrue(source.contains("data?.source?.kind !== \"user\""))
        XCTAssertTrue(source.contains("type === \"assistant/message\""))
        XCTAssertTrue(source.contains("type === \"tool/call\""))
        XCTAssertTrue(source.contains("type === \"tool/result\""))
        XCTAssertTrue(source.contains("type === \"approval/asked\""))
        XCTAssertTrue(source.contains("type === \"todo/write\""))
        XCTAssertTrue(source.contains("type === \"turn/end\""))
        XCTAssertTrue(source.contains("hook_event_name: \"PermissionRequest\""))
        XCTAssertTrue(source.contains("notification_type: \"assistant_message\""))
        XCTAssertTrue(source.contains("stdio: [\"pipe\", \"ignore\", \"ignore\"]"))
        XCTAssertTrue(source.contains("_source: \"dsh\""))
        XCTAssertFalse(source.contains("data.arguments"))
        XCTAssertFalse(source.contains("tool_input"))
        XCTAssertFalse(source.contains("tool_result"))
        XCTAssertFalse(source.contains("approval.request"))
        XCTAssertFalse(source.contains("approval.decide"))
    }

    func testDSHPatchInstallIsIdempotentAndPreservesUserRows() {
        let pluginURL = URL(fileURLWithPath: "/Users/example/.dsh/plugins/mac-island/index.mjs")
        let existing = """
            # user-owned row
            - id: user-plugin
              name: '@example/plugin'
            """

        let first = HookInstaller.updatedDSHPatch(
            existing: existing,
            pluginURL: pluginURL,
            installing: true
        )
        let second = HookInstaller.updatedDSHPatch(
            existing: first,
            pluginURL: pluginURL,
            installing: true
        )

        XCTAssertEqual(first, second)
        XCTAssertTrue(second.contains("id: user-plugin"))
        XCTAssertTrue(second.contains("id: mac-island-observer"))
        XCTAssertTrue(HookInstaller.containsManagedDSHPatch(second, pluginURL: pluginURL))
        XCTAssertEqual(second.components(separatedBy: "dsh-hooks begin").count - 1, 1)

        let removed = HookInstaller.updatedDSHPatch(
            existing: second,
            pluginURL: pluginURL,
            installing: false
        )
        XCTAssertTrue(removed.contains("id: user-plugin"))
        XCTAssertFalse(removed.contains("mac-island-observer"))
        XCTAssertFalse(removed.contains("dsh-hooks begin"))
    }

    func testDSHDirectoryInstallAlwaysActivatesTheESMEntrypoint() {
        let directoryURL = URL(fileURLWithPath: "/Users/example/.dsh/plugins/mac-island", isDirectory: true)
        let entryURL = HookInstaller.dshPluginEntryURL(for: directoryURL)
        let patch = HookInstaller.updatedDSHPatch(
            existing: nil,
            pluginURL: entryURL,
            installing: true
        )

        XCTAssertEqual(entryURL.lastPathComponent, "index.mjs")
        XCTAssertTrue(patch.contains("file:///Users/example/.dsh/plugins/mac-island/index.mjs"))
        XCTAssertFalse(patch.contains("name: 'file:///Users/example/.dsh/plugins/mac-island/'"))
    }

    func testEmptyDSHPatchRoundTripRemainsValidYAMLArray() {
        let pluginURL = URL(fileURLWithPath: "/Users/example/.dsh/plugins/mac-island/index.mjs")
        let installed = HookInstaller.updatedDSHPatch(
            existing: "# local preferences\n[]\n",
            pluginURL: pluginURL,
            installing: true
        )
        XCTAssertFalse(installed.components(separatedBy: .newlines).contains("[]"))

        let removed = HookInstaller.updatedDSHPatch(
            existing: installed,
            pluginURL: pluginURL,
            installing: false
        )
        XCTAssertTrue(removed.contains("# local preferences"))
        XCTAssertTrue(removed.components(separatedBy: .newlines).contains("[]"))
    }

    func testRuntimeProfileAndPolicyRecognizeCLIAndLocalWeb() throws {
        let runtime = ClientProfileRegistry.matchRuntimeProfile(
            provider: .claude,
            explicitKind: "dsh",
            explicitName: "DeepSeek Harness",
            explicitBundleIdentifier: nil,
            terminalBundleIdentifier: nil,
            origin: "web",
            originator: "DeepSeek Harness",
            threadSource: "dsh-plugin",
            processName: "dsh"
        )
        XCTAssertEqual(runtime?.id, "dsh")
        XCTAssertEqual(runtime?.displayName, "DeepSeek Harness")

        let web = SessionClientInfo(
            kind: .custom,
            profileID: "dsh",
            name: "DeepSeek Harness Web",
            launchURL: "http://127.0.0.1:3080",
            origin: "web",
            originator: "DeepSeek Harness",
            threadSource: "dsh-plugin"
        )
        XCTAssertTrue(web.isDSHClient)
        XCTAssertFalse(web.isClaudeCodeClient)
        XCTAssertTrue(web.prefersHookMessageAsLastMessageFallback)
        XCTAssertTrue(MacIslandProductPolicy.supportsSession(provider: .claude, clientInfo: web))

        var cron = web
        cron.origin = "cron"
        XCTAssertFalse(MacIslandProductPolicy.supportsSession(provider: .claude, clientInfo: cron))
    }

    func testSnapshotAndGlyphUseDSHIdentity() throws {
        let info = SessionClientInfo(
            kind: .custom,
            profileID: "dsh",
            name: "DeepSeek Harness",
            origin: "cli",
            originator: "DeepSeek Harness",
            threadSource: "dsh-plugin"
        )
        let session = SessionState(
            sessionId: "dsh-session",
            cwd: "/tmp/project",
            provider: .claude,
            clientInfo: info,
            phase: .processing
        )

        XCTAssertEqual(MacIslandClientGlyphKind(session: session), .dsh)
        XCTAssertEqual(MacIslandSessionSnapshot.make(from: session)?.client, .dsh)
        XCTAssertTrue(
            MacIslandClientGlyphMotionPolicy.shouldAnimate(
                kind: .dsh,
                status: .working,
                reduceMotion: false,
                animationLevel: .full
            )
        )
        XCTAssertFalse(
            MacIslandClientGlyphMotionPolicy.shouldAnimate(
                kind: .dsh,
                status: .idle,
                reduceMotion: false,
                animationLevel: .full
            )
        )
        XCTAssertNotEqual(
            MacIslandDSHGlyphMotion.state(at: 0.2),
            MacIslandDSHGlyphMotion.state(at: 1.1)
        )
    }
}
