import AppKit
import SwiftUI

/// A deliberate action opens one reusable, accessible preview window on either surface.
@MainActor
final class SessionContinuationWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SessionContinuationWindowController()
    private(set) var presentedSessionID: String?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 440, height: 360)
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(_ session: SessionState, activatesApplication: Bool = true) {
        guard let window else { return }
        window.title = AppLocalization.string("续接预览")
        if presentedSessionID != session.sessionId {
            cancelCurrentPreparation()
            window.contentView = NSHostingView(
                rootView: AppLocalizedRootView {
                    SessionContinuationPreviewView(
                        session: session, onClose: { [weak self] in self?.close() }
                    )
                })
            presentedSessionID = session.sessionId
        }
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        if activatesApplication { NSApp.activate(ignoringOtherApps: true) }
    }

    func windowWillClose(_ notification: Notification) {
        cancelCurrentPreparation()
        // Unmounting cancels the SwiftUI task and invalidates its prepared token.
        window?.contentView = nil
        presentedSessionID = nil
    }

    private func cancelCurrentPreparation() {
        if let presentedSessionID {
            SessionContinuationService.shared.cancelPreparation(sessionKey: presentedSessionID)
        }
    }
}
