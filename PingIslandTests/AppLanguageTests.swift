import XCTest

@testable import Ping_Island

final class AppLanguageTests: XCTestCase {
    func testSystemLanguagePrefersSimplifiedChineseForChineseLocales() {
        XCTAssertEqual(
            AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["zh-Hans-CN"]),
            "zh-Hans"
        )
        XCTAssertEqual(
            AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["zh-TW"]),
            "zh-Hans"
        )
    }

    func testSystemLanguageFallsBackToEnglishForNonChineseLocales() {
        XCTAssertEqual(
            AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["en-US"]),
            "en"
        )
        XCTAssertEqual(
            AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["ja-JP"]),
            "en"
        )
    }

    func testExplicitLanguageSelectionsStayStable() {
        XCTAssertEqual(AppLanguage.simplifiedChinese.resolvedLanguageCode(), "zh-Hans")
        XCTAssertEqual(AppLanguage.english.resolvedLanguageCode(), "en")
    }

    @MainActor
    func testResourceLanguageFollowsSelectedLocaleInsteadOfSystemLanguage() {
        XCTAssertEqual(
            AppLocalization.string("screen-privacy.mode.titles", locale: Locale(identifier: "en_US")), "Titles")
        XCTAssertEqual(
            AppLocalization.string("screen-privacy.mode.titles", locale: Locale(identifier: "zh_Hans_CN")), "显示标题")
        XCTAssertEqual(
            AppLocalization.format("在 %@ 打开", "Codex", locale: Locale(identifier: "en")), "Open in Codex")
        XCTAssertEqual(
            AppLocalization.format("在 %@ 打开", "Codex", locale: Locale(identifier: "zh-Hans")), "在 Codex 打开")
    }

    @MainActor
    func testLocalizedFormattingPreservesArgumentTextAndUnknownKeys() {
        let title = "Example 100% %@ 中文"
        XCTAssertEqual(
            AppLocalization.format("在 %@ 打开", title, locale: Locale(identifier: "en")), "Open in " + title)
        XCTAssertEqual(
            AppLocalization.string("synthetic.missing-key", locale: Locale(identifier: "zh-Hans")),
            "synthetic.missing-key")
    }
}
