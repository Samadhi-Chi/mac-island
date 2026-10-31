import AppKit
import SwiftUI

/// A mounted list owns keys only in its own window, regardless of Island surface.
@MainActor
final class SessionListKeyboardScope {
    weak var window: NSWindow?

    // Releasing the weak reference needs no actor hop. An implicit isolated
    // deinit crashes on older Swift runtimes (swiftlang/swift#85663).
    nonisolated deinit {}

    func accepts(_ event: NSEvent, keyWindow: NSWindow?) -> Bool {
        guard let window, keyWindow === window,
            event.windowNumber == window.windowNumber,
            event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        else {
            return false
        }
        if let editor = window.firstResponder as? NSTextView, editor.isEditable { return false }
        return true
    }
}

struct SessionListWindowProbe: NSViewRepresentable {
    let scope: SessionListKeyboardScope

    func makeNSView(context: Context) -> ProbeView { ProbeView(scope: scope) }
    func updateNSView(_ view: ProbeView, context: Context) {}

    final class ProbeView: NSView {
        let scope: SessionListKeyboardScope
        init(scope: SessionListKeyboardScope) {
            self.scope = scope
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scope.window = window
        }
    }
}
