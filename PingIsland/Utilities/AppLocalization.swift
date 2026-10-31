import Foundation
import SwiftUI

@MainActor
enum AppLocalization {
    private static let languageBundles: [String: Bundle] = ["en", "zh-Hans"].reduce(into: [:]) { bundles, code in
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) {
            bundles[code] = bundle
        }
    }

    static func string(_ key: String) -> String {
        string(key, locale: AppSettings.shared.locale)
    }

    static func string(_ key: String, locale: Locale) -> String {
        // Select the resource language explicitly. Locale alone controls value
        // formatting but can leave Bundle.main using the system's preferred language.
        let code = locale.language.languageCode?.identifier == "zh" ? "zh-Hans" : "en"
        return (languageBundles[code] ?? .main).localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        format(key, arguments: arguments, locale: AppSettings.shared.locale)
    }

    static func format(_ key: String, _ arguments: CVarArg..., locale: Locale) -> String {
        format(key, arguments: arguments, locale: locale)
    }

    private static func format(_ key: String, arguments: [CVarArg], locale: Locale) -> String {
        let format = string(key, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }
}

struct AppLocalizedRootView<Content: View>: View {
    @ObservedObject private var settings = AppSettings.shared
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.locale, settings.locale)
    }
}

extension Text {
    init(appLocalized key: String) {
        self.init(LocalizedStringKey(key))
    }
}
