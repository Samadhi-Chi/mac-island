import CoreGraphics

enum SettingsWindowDefaults {
    nonisolated static let sidebarWidth: CGFloat = 252
    nonisolated static let defaultDetailWidth: CGFloat = 708
    nonisolated static let defaultContentSize = CGSize(
        width: sidebarWidth + defaultDetailWidth,
        height: 700
    )
}
