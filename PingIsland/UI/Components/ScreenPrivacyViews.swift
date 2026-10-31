import SwiftUI

struct ScreenPrivacyToggleButton: View {
    @ObservedObject private var privacy = ScreenPrivacyStore.shared

    var body: some View {
        Button {
            // Do not animate sensitive content away: remove it in this update.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { privacy.toggleTemporaryHiding() }
        } label: {
            Label {
                Text(
                    appLocalized: privacy.isTemporarilyHidden
                        ? "screen-privacy.restore" : "screen-privacy.hide")
            } icon: {
                Image(systemName: privacy.isTemporarilyHidden ? "eye.slash.fill" : "eye.slash")
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("screen-privacy.temporary-toggle")
        .accessibilityValue(
            Text(
                appLocalized: privacy.isTemporarilyHidden
                    ? "screen-privacy.hidden" : privacy.mode.localizationKey))
    }
}

/// An intentionally small row shared by current and recent restricted screens.
/// Only a native title and fixed client/status labels enter the rendered tree.
struct ScreenPrivacySessionRow: View {
    let presentation: ScreenSessionPresentation
    let showsTitles: Bool
    let selected: Bool
    var navigationEnabled = true
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                if showsTitles {
                    if let title = presentation.title {
                        Text(verbatim: title).fontWeight(.semibold).lineLimit(1)
                    } else {
                        Text(appLocalized: "标题暂不可用").fontWeight(.semibold)
                    }
                } else {
                    Text(verbatim: presentation.clientName).fontWeight(.semibold)
                }
                HStack(spacing: 5) {
                    if showsTitles { Text(verbatim: presentation.clientName) }
                    Text(appLocalized: presentation.statusKey)
                }
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if navigationEnabled {
                Button(action: onOpen) {
                    Text(verbatim: AppLocalization.format("在 %@ 打开", presentation.clientName))
                }
                .buttonStyle(.plain).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.blue)
            }
        }
        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.9))
        .padding(10)
        .background(.white.opacity(selected ? 0.13 : 0.045), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle()).onTapGesture(perform: onSelect)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-privacy.session-row")
    }
}
