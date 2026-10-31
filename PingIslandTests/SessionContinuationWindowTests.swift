import AppKit
import XCTest

@testable import Ping_Island

@MainActor
final class SessionContinuationWindowTests: XCTestCase {
    func testRepeatedPreviewReusesWindowAndContentUntilTargetChanges() throws {
        let controller = SessionContinuationWindowController()
        defer { controller.close() }
        // Unsupported desktop fixtures fail before any executable or directory probe.
        let first = fixture("preview-window-first")
        controller.present(first, activatesApplication: false)
        let window = try XCTUnwrap(controller.window)
        let originalContent = try XCTUnwrap(window.contentView)
        controller.present(first, activatesApplication: false)
        XCTAssertTrue(controller.window === window)
        XCTAssertTrue(window.contentView === originalContent)
        XCTAssertEqual(controller.presentedSessionID, first.sessionId)

        controller.present(fixture("preview-window-second"), activatesApplication: false)
        XCTAssertTrue(controller.window === window)
        XCTAssertFalse(window.contentView === originalContent)
        XCTAssertEqual(controller.presentedSessionID, "preview-window-second")
    }

    func testCloseUnmountsPreviewAndAllowsFreshPresentation() throws {
        let controller = SessionContinuationWindowController()
        defer { controller.close() }
        let session = fixture("preview-window-close")
        controller.present(session, activatesApplication: false)
        let window = try XCTUnwrap(controller.window)
        controller.close()
        XCTAssertNil(controller.presentedSessionID)
        XCTAssertNil(window.contentView)
        XCTAssertFalse(window.isVisible)
        controller.present(session, activatesApplication: false)
        XCTAssertEqual(controller.presentedSessionID, session.sessionId)
        XCTAssertNotNil(window.contentView)
    }

    private func fixture(_ id: String) -> SessionState {
        SessionState(
            sessionId: id, cwd: "/nonexistent/preview-window-fixture",
            provider: .codex, clientInfo: .codexApp(threadId: id), phase: .ended)
    }
}
