import Combine
import Foundation

/// Screen presentation only. These choices never change source data, monitoring,
/// or the content-free persistence and diagnostics contracts.
enum ScreenContentVisibility: String, CaseIterable, Identifiable, Sendable {
    case statusOnly
    case titles
    case details

    nonisolated var id: String { rawValue }
    nonisolated var localizationKey: String { "screen-privacy.mode.\(rawValue)" }
    nonisolated var showsTitles: Bool { self != .statusOnly }
    nonisolated var showsDetails: Bool { self == .details }

    nonisolated static let settingsKey = "macIslandScreenContentVisibility"

    /// Called before AppSettings stamps its preset version on a fresh install.
    /// An unknown saved value fails closed rather than restoring rich content.
    nonisolated static func preparePreference(defaults: UserDefaults, previousPresetVersion: Int) {
        guard defaults.object(forKey: settingsKey) == nil else { return }
        defaults.set((previousPresetVersion > 0 ? Self.details : .titles).rawValue, forKey: settingsKey)
    }
}

@MainActor
final class ScreenPrivacyStore: ObservableObject {
    nonisolated deinit {}

    static let shared: ScreenPrivacyStore = {
        let isolated = !SessionMonitor.allowsLiveMonitoring()
        // Prepare migration before any view constructs the screen store.
        if !isolated { _ = AppSettings.shared }
        return ScreenPrivacyStore(defaults: isolated ? nil : .standard)
    }()

    @Published var mode: ScreenContentVisibility {
        didSet { defaults?.set(mode.rawValue, forKey: ScreenContentVisibility.settingsKey) }
    }
    /// Deliberately never persisted: restoring reveals the user's chosen level.
    @Published private(set) var isTemporarilyHidden = false
    private let defaults: UserDefaults?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        mode =
            defaults?.string(forKey: ScreenContentVisibility.settingsKey)
            .flatMap(ScreenContentVisibility.init(rawValue:)) ?? MacIslandProductPolicy.defaultScreenContentVisibility
    }

    var effectiveMode: ScreenContentVisibility { isTemporarilyHidden ? .statusOnly : mode }

    func toggleTemporaryHiding() { isTemporarilyHidden.toggle() }
}

/// The restricted row receives an allowlisted value, not a conversation preview.
/// No paths, native IDs, tool labels, model names, or source-derived summaries.
struct ScreenSessionPresentation: Equatable, Sendable {
    let title: String?
    let clientName: String
    let statusKey: String

    init(session: SessionState, title: SessionListTitle, mode: ScreenContentVisibility) {
        self.title = mode.showsTitles ? title.nativeName.map { String($0.prefix(512)) } : nil
        clientName =
            RecentSessionRecord(session: session)?.clientName
            ?? session.provider.displayName
        if session.needsAttention {
            statusKey = "screen-privacy.status.attention"
        } else {
            statusKey =
                switch session.phase {
                case .processing: "screen-privacy.status.working"
                case .compacting: "screen-privacy.status.compacting"
                case .ended: "screen-privacy.status.ended"
                case .waitingForInput: "screen-privacy.status.waiting"
                case .waitingForApproval: "screen-privacy.status.attention"
                case .idle: "screen-privacy.status.idle"
                }
        }
    }

    init(record: RecentSessionRecord, title: SessionListTitle, mode: ScreenContentVisibility) {
        self.title = mode.showsTitles ? title.nativeName.map { String($0.prefix(512)) } : nil
        clientName = record.clientName
        statusKey = "screen-privacy.status.recent"
    }
}

nonisolated struct ScreenPersonalAgentPresentation: Equatable, Sendable {
    let name: String
    let activities: [String]

    init(observation: PersonalAgentObservation, mode: ScreenContentVisibility, unavailableName: String) {
        name = mode.showsTitles ? (observation.agentName ?? unavailableName) : observation.client.name
        activities = mode.showsDetails ? observation.nativeActivityLabels : []
    }
}
