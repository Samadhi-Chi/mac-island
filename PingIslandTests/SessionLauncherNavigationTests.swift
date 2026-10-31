import XCTest

@testable import Ping_Island

@MainActor
final class SessionLauncherNavigationTests: XCTestCase {
    func testAcceptedCodexURLRemainsARequestEvenWhenAppActivationSucceeds() async {
        let calls = NavigationCalls()
        let launcher = SessionLauncher(
            urlOpener: { url in
                await calls.record(url)
                return true
            },
            applicationActivator: { bundle in
                await calls.record(bundle)
                return true
            }
        )
        let result = await launcher.navigate(codexFixture())
        XCTAssertEqual(result, .requestSent(.sessionLink))
        let urls = await calls.urls
        let bundles = await calls.bundles
        XCTAssertEqual(urls, ["codex://threads/navigation-fixture"])
        XCTAssertEqual(bundles, ["com.openai.codex"])
    }

    func testAcceptedURLIsStillDispatchedWhenAppActivationReturnsFalse() async {
        let launcher = SessionLauncher(urlOpener: { _ in true }, applicationActivator: { _ in false })
        let result = await launcher.navigate(codexFixture())
        XCTAssertEqual(result, .requestSent(.sessionLink))
    }

    private func codexFixture() -> SessionState {
        SessionState(
            sessionId: "navigation-fixture", cwd: "/nonexistent/island-navigation-fixture",
            provider: .codex, clientInfo: .codexApp(threadId: "navigation-fixture")
        )
    }
}

private actor NavigationCalls {
    private(set) var urls: [String] = []
    private(set) var bundles: [String] = []
    func record(_ url: URL) { urls.append(url.absoluteString) }
    func record(_ bundle: String) { bundles.append(bundle) }
}
