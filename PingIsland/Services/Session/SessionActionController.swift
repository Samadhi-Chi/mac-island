import AppKit
import Combine
import Foundation

/// One coordinator for explicit actions from either Island presentation.
/// Feedback is transient; it never persists a session snapshot or conversation.
@MainActor
final class SessionActionController: ObservableObject {
    // Only value/reference state is released here. Avoid the older macOS
    // main-actor deinit back-deployment runtime, as in the other UI coordinators.
    nonisolated deinit {}
    static let shared = SessionActionController(navigator: SessionLauncher.shared)

    struct Feedback: Equatable {
        let sessionID: String
        let clientName: String
        let result: SessionNavigationResult?
        var recordID: String? = nil

        func matches(_ session: SessionState) -> Bool {
            if let recordID { return recordID == RecentSessionRecord(session: session)?.id }
            return sessionID == session.sessionId
        }

        func matches(_ record: RecentSessionRecord) -> Bool {
            recordID == record.id
        }
    }

    @Published private(set) var feedback: Feedback?
    @Published private(set) var activeSessionIDs: Set<String> = []
    private let navigator: any SessionNavigating
    private var generation: UInt64 = 0

    init(navigator: any SessionNavigating) {
        self.navigator = navigator
    }

    func perform(
        _ session: SessionState,
        action: SessionNavigationAction = .returnToSession
    ) async {
        guard session.clientInfo.origin != "unknown" else {
            report(.unavailable(.navigationSuppressed), for: session)
            return
        }
        // The native/observed key stays stable when a PID changes. Deduplicate
        // across both buttons as opening an app may also navigate its session.
        guard activeSessionIDs.insert(session.sessionId).inserted else { return }
        generation &+= 1
        let requestGeneration = generation
        feedback = makeFeedback(for: session, result: nil)
        let result: SessionNavigationResult
        switch action {
        case .returnToSession: result = await navigator.navigate(session)
        case .openApplication: result = await navigator.openClientApplication(session)
        }
        activeSessionIDs.remove(session.sessionId)
        guard requestGeneration == generation else { return }
        feedback = makeFeedback(for: session, result: result)
    }

    func dismissFeedback() {
        generation &+= 1
        feedback = nil
    }

    /// Other explicit actions can share the same presentation and supersede an
    /// older navigation result without starting another navigation request.
    func report(_ result: SessionNavigationResult, for session: SessionState) {
        generation &+= 1
        feedback = makeFeedback(for: session, result: result)
    }

    private func makeFeedback(for session: SessionState, result: SessionNavigationResult?) -> Feedback {
        Feedback(
            sessionID: session.sessionId, clientName: SessionListPresentation.clientName(for: session),
            result: result, recordID: RecentSessionRecord(session: session)?.id)
    }

    func copyNativeSessionID(_ session: SessionState) {
        let nativeID = SessionNavigationIdentity.nativeSessionID(for: session)
        NSPasteboard.general.clearContents()
        report(
            NSPasteboard.general.setString(nativeID, forType: .string)
                ? .completed(.copiedSessionID) : .failed(.clipboardUnavailable), for: session)
    }

    func openProject(_ session: SessionState) {
        var isDirectory: ObjCBool = false
        guard !session.isRemoteSession, session.cwd.hasPrefix("/"),
            !session.cwd.contains("\0"),
            FileManager.default.fileExists(atPath: session.cwd, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            report(.unavailable(.invalidWorkspace), for: session)
            return
        }
        let opened = NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd, isDirectory: true))
        report(opened ? .requestSent(.workspace) : .failed(.targetNotFound), for: session)
    }

    func hideLocally(_ session: SessionState, using hide: (SessionState) -> Void) {
        hide(session)
        report(.completed(.hiddenLocally), for: session)
    }
}
