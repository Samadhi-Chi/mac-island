import SwiftUI

enum UsageQuotaPalette {
    /// macOS system battery-style colors: green, yellow, and red.
    static func foreground(for severity: UsageSummarySeverity) -> Color {
        switch severity {
        case .healthy:
            return Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
        case .warning:
            return Color(red: 255 / 255, green: 214 / 255, blue: 10 / 255)
        case .critical:
            return Color(red: 255 / 255, green: 69 / 255, blue: 58 / 255)
        }
    }

    static func background(for severity: UsageSummarySeverity) -> Color {
        foreground(for: severity).opacity(severity == .critical ? 0.20 : 0.16)
    }
}
