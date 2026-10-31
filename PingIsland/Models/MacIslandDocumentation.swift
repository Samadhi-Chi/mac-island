import Foundation

/// Offline product documentation is available even before a public site exists.
enum MacIslandDocumentation: String, CaseIterable, Identifiable {
    case help, privacy, acknowledgements

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .help: "使用与兼容说明"
        case .privacy: "隐私说明"
        case .acknowledgements: "开源许可与致谢"
        }
    }

    func resourceName(locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier == "zh" ? "zh-Hans" : "en"
        switch self {
        case .help: return "MacIsland-Help-\(language)"
        case .privacy: return "MacIsland-Privacy-\(language)"
        case .acknowledgements: return "MacIsland-ThirdPartyNotices"
        }
    }

    func content(locale: Locale, bundle: Bundle = .main) -> String? {
        let name = resourceName(locale: locale)
        let suffix = self == .acknowledgements ? "txt" : "md"
        // Xcode may preserve resource directories or flatten synchronized groups.
        let url =
            bundle.url(forResource: name, withExtension: suffix)
            ?? bundle.url(forResource: name, withExtension: suffix, subdirectory: "Legal")
            ?? bundle.url(forResource: name, withExtension: suffix, subdirectory: "Resources/Legal")
        guard let url else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// Only explicit user actions open distribution pages. No update polling or
/// session metadata is sent, and an unconfigured build never invents a URL.
struct MacIslandDistributionLinks {
    let website: URL?
    let support: URL?

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        website = Self.publicHTTPSURL(info["MacIslandWebsiteURL"] as? String)
        support = Self.publicHTTPSURL(info["MacIslandSupportURL"] as? String)
    }

    private static func publicHTTPSURL(_ value: String?) -> URL? {
        guard let value, !value.contains("$("),
            let parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
            parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
            let host = parts.host?.lowercased(), host.contains("."),
            !["example.com", "example.org", "example.net", "localhost"].contains(host),
            !host.hasSuffix(".invalid"), !host.hasSuffix(".localhost"),
            !host.hasSuffix(".example"), let url = parts.url
        else { return nil }
        return url
    }
}
