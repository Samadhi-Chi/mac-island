import AppKit
import XCTest

@testable import Ping_Island

@MainActor
final class SessionListKeyboardScopeTests: XCTestCase {
    func testBothIslandWindowsAcceptTheirOwnListKeys() throws {
        for window in [makeWindow(NotchPanel.self), makeWindow(DetachedIslandWindow.self)] {
            defer { window.close() }
            let scope = SessionListKeyboardScope()
            let probe = SessionListWindowProbe.ProbeView(scope: scope)
            window.contentView = probe
            XCTAssertTrue(scope.window === window)
            XCTAssertTrue(scope.accepts(try keyEvent(in: window), keyWindow: window))
            window.contentView = nil
            XCTAssertNil(scope.window)
        }
    }

    func testOtherWindowsAndDetachedListsDoNotConsumeKeys() throws {
        let host = makeWindow(DetachedIslandWindow.self)
        let other = makeWindow(NSWindow.self)
        defer {
            host.close()
            other.close()
        }
        let scope = SessionListKeyboardScope()
        scope.window = host
        XCTAssertFalse(scope.accepts(try keyEvent(in: host), keyWindow: other))
        XCTAssertFalse(scope.accepts(try keyEvent(in: other), keyWindow: host))
        scope.window = nil
        XCTAssertFalse(scope.accepts(try keyEvent(in: host), keyWindow: host))
    }

    func testModifiedKeysRemainAvailableToMenusAndSystemActions() throws {
        let window = makeWindow(NotchPanel.self)
        defer { window.close() }
        let scope = SessionListKeyboardScope()
        scope.window = window
        for modifier in [NSEvent.ModifierFlags.command, .control, .option] {
            XCTAssertFalse(scope.accepts(try keyEvent(in: window, modifiers: modifier), keyWindow: window))
        }
    }

    func testEditableTextKeepsArrowAndReturnKeys() throws {
        let window = makeWindow(DetachedIslandWindow.self)
        defer { window.close() }
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        window.contentView = editor
        XCTAssertTrue(window.makeFirstResponder(editor))
        let scope = SessionListKeyboardScope()
        scope.window = window
        XCTAssertFalse(scope.accepts(try keyEvent(in: window), keyWindow: window))
    }

    private func makeWindow(_ type: NSWindow.Type) -> NSWindow {
        let window = type.init(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private func keyEvent(in window: NSWindow, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: "\r", charactersIgnoringModifiers: "\r",
                isARepeat: false, keyCode: 36))
    }
}
