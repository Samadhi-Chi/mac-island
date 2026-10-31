import SwiftUI

struct PersonalAgentObservationRow: View {
    let observation: PersonalAgentObservation
    let selected: Bool
    let onSelect: () -> Void
    @State private var activitiesExpanded = false
    @State private var iconInteractionActive = false
    @ObservedObject private var monitor = PersonalAgentMonitor.shared
    @ObservedObject private var privacy = ScreenPrivacyStore.shared

    private var screenPresentation: ScreenPersonalAgentPresentation {
        ScreenPersonalAgentPresentation(
            observation: observation, mode: privacy.effectiveMode,
            unavailableName: AppLocalization.string("personal-agent.bot-name.unavailable"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 9) {
                MacIslandClientGlyphView(
                    kind: .init(personalAgent: observation.client), status: .idle,
                    size: 24, interactionActive: iconInteractionActive
                )
                .accessibilityIdentifier("personal-agent.glyph.\(observation.client.rawValue)")
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: screenPresentation.name)
                        .font(.system(size: 12, weight: .semibold)).lineLimit(2)
                    Text(
                        verbatim: "\(observation.client.name) · \(AppLocalization.string("personal-agent.bot.current"))"
                    )
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 4)
                Button {
                    monitor.openApplication(observation.client)
                } label: {
                    Text(appLocalized: "personal-agent.open-app")
                }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                .accessibilityIdentifier("personal-agent.open.\(observation.client.rawValue)")
            }
            if let preview = screenPresentation.activities.first {
                if !activitiesExpanded {
                    Text(verbatim: preview).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2).padding(.leading, 33)
                }
                Button {
                    onSelect()
                    activitiesExpanded.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: activitiesExpanded ? "chevron.down" : "chevron.right")
                        Text(
                            verbatim: AppLocalization.format(
                                "personal-agent.activities.count", screenPresentation.activities.count))
                        Text(
                            appLocalized: activitiesExpanded
                                ? "personal-agent.activities.collapse" : "personal-agent.activities.expand")
                    }
                }
                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
                .padding(.leading, 33)
                .accessibilityIdentifier("personal-agent.activities.\(observation.client.rawValue)")
                .accessibilityValue(
                    Text(
                        appLocalized: activitiesExpanded
                            ? "personal-agent.activities.expanded" : "personal-agent.activities.collapsed"))
                if activitiesExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(screenPresentation.activities.enumerated()), id: \.offset) { _, label in
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName: "clock.arrow.circlepath").font(.system(size: 10))
                                Text(verbatim: label).font(.system(size: 11)).fixedSize(
                                    horizontal: false, vertical: true)
                            }
                        }
                    }
                    .foregroundStyle(.white.opacity(0.65)).padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.04)))
                    .padding(.leading, 33)
                    .accessibilityIdentifier("personal-agent.activity-details.\(observation.client.rawValue)")
                }
            } else if privacy.effectiveMode.showsDetails {
                Text(
                    appLocalized: observation.client == .muse
                        ? (observation.scope == .visibleActivity
                            ? "personal-agent.activities.empty" : "personal-agent.activities.open-muse")
                        : "personal-agent.activities.unavailable"
                )
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).padding(.leading, 33)
            }
            HStack(spacing: 6) {
                Text(appLocalized: observation.statusLocalizationKey)
                Spacer(minLength: 4)
                Text(appLocalized: "personal-agent.verified")
                Text(observation.observedAt, style: .time)
            }
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(selected ? 0.13 : 0.045)))
        .contentShape(Rectangle()).onTapGesture(perform: onSelect)
        .onHover { iconInteractionActive = $0 }
        .onDisappear { iconInteractionActive = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("personal-agent.observation.\(observation.client.rawValue)")
    }
}

struct PersonalAgentNavigationFeedback: View {
    let client: PersonalAgentClient
    let opened: Bool
    let onDismiss: () -> Void
    var islandStyle = false

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: opened ? "info.circle" : "exclamationmark.circle")
            Text(appLocalized: opened ? "personal-agent.navigation.app-only" : "personal-agent.navigation.failed")
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel(Text(appLocalized: "personal-agent.dismiss"))
        }
        .font(.system(size: 11))
        .foregroundStyle(islandStyle ? Color.white.opacity(0.7) : Color.secondary)
        .accessibilityIdentifier("personal-agent.navigation.\(client.rawValue)")
    }
}

/// An enabled source without verified Bot metadata is not a session or history.
struct PersonalAgentSourceStatusRow: View {
    let client: PersonalAgentClient
    let health: PersonalAgentHealth
    let onOpen: () -> Void
    @State private var iconInteractionActive = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            MacIslandClientGlyphView(
                kind: .init(personalAgent: client), status: .idle,
                size: 24, interactionActive: iconInteractionActive)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: client.name).font(.system(size: 12, weight: .semibold))
                Text(appLocalized: "personal-agent.source.unavailable")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
                Text(appLocalized: health.phase.localizationKey)
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                if let version = health.version, !version.isEmpty {
                    Text(verbatim: "v\(version)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer(minLength: 4)
            Button(action: onOpen) { Text(appLocalized: "personal-agent.open-app") }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white.opacity(0.9)).padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.045)))
        .onHover { iconInteractionActive = $0 }
        .onDisappear { iconInteractionActive = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("personal-agent.source-state.\(client.rawValue)")
    }
}

struct PersonalAgentSettingsView: View {
    @ObservedObject private var monitor = PersonalAgentMonitor.shared

    var body: some View {
        SettingsSectionCard(title: "personal-agent.settings.title") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(PersonalAgentClient.allCases) { client in
                    if client != PersonalAgentClient.allCases.first { Divider().padding(.horizontal, 14) }
                    clientRow(client).padding(14)
                }
                Divider().padding(.horizontal, 14)
                VStack(alignment: .leading, spacing: 9) {
                    Text(appLocalized: "personal-agent.settings.privacy").font(.system(size: 11)).foregroundStyle(
                        .secondary)
                    HStack(spacing: 12) {
                        Button {
                            monitor.requestAccessibilityPermission()
                        } label: {
                            Text(appLocalized: "personal-agent.settings.permission")
                        }
                        .accessibilityIdentifier("settings.personal-agent.permission")
                        Button {
                            monitor.requestRefresh()
                        } label: {
                            Text(appLocalized: "personal-agent.settings.refresh")
                        }
                        .accessibilityIdentifier("settings.personal-agent.refresh")
                    }
                    .buttonStyle(.borderless)
                }.padding(14)
            }
        }
        .tint(Color(nsColor: .controlAccentColor))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.personal-agents")
    }

    private func clientRow(_ client: PersonalAgentClient) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                if client.canObserve {
                    MacIslandClientGlyphView(kind: .init(personalAgent: client), status: .idle, size: 24)
                        .accessibilityIdentifier("settings.personal-agent.glyph.\(client.rawValue)")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: client.name).font(.system(size: 13, weight: .semibold))
                    Text(
                        appLocalized: client.canObserve
                            ? "personal-agent.settings.experimental" : "personal-agent.settings.dot-unavailable"
                    )
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if client.canObserve {
                    Toggle(
                        isOn: Binding(
                            get: { monitor.enabled.contains(client) }, set: { monitor.setEnabled($0, for: client) })
                    ) {
                        Text(appLocalized: "personal-agent.settings.enable")
                    }
                    .toggleStyle(.switch).labelsHidden()
                    .accessibilityIdentifier("settings.personal-agent.enable.\(client.rawValue)")
                }
            }
            let status = monitor.health[client] ?? .init(phase: client.canObserve ? .disabled : .sourceUnavailable)
            Text(appLocalized: status.phase.localizationKey).font(.system(size: 11)).foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.personal-agent.health.\(client.rawValue)")
            if let time = status.lastSuccessfulRead {
                HStack(spacing: 5) {
                    Text(appLocalized: "personal-agent.verified")
                    Text(time, style: .time)
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let version = status.version, !version.isEmpty {
                Text(verbatim: "v\(version)").font(.system(size: 10)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.personal-agent.version.\(client.rawValue)")
            }
            HStack(spacing: 12) {
                if client.canObserve, monitor.enabled.contains(client) {
                    Button {
                        monitor.setPaused(!monitor.paused.contains(client), for: client)
                    } label: {
                        Text(
                            appLocalized: monitor.paused.contains(client)
                                ? "personal-agent.settings.resume" : "personal-agent.settings.pause")
                    }
                    .accessibilityIdentifier("settings.personal-agent.pause.\(client.rawValue)")
                }
                Button {
                    monitor.openApplication(client)
                } label: {
                    Text(
                        appLocalized: client == .dot
                            ? "personal-agent.settings.open-dot-app" : "personal-agent.open-app")
                }
                .accessibilityIdentifier("settings.personal-agent.open.\(client.rawValue)")
            }.buttonStyle(.borderless)
            if let opened = monitor.navigationFeedback[client] {
                PersonalAgentNavigationFeedback(client: client, opened: opened) {
                    monitor.dismissNavigationFeedback(client)
                }
            }
        }
    }
}
