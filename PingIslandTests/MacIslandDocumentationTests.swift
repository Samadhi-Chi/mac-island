import XCTest

@testable import Ping_Island

@MainActor
final class MacIslandDocumentationTests: XCTestCase {
    func testAllOfflineDocumentsAreBundledForBothLanguages() throws {
        for document in MacIslandDocumentation.allCases {
            for identifier in ["en", "zh-Hans"] {
                let text = try XCTUnwrap(document.content(locale: Locale(identifier: identifier)))
                XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertTrue(text.contains("Mac Island"))
            }
        }
    }

    func testThirdPartyNoticesIncludeRedistributedComponents() throws {
        let text = try XCTUnwrap(MacIslandDocumentation.acknowledgements.content(locale: Locale(identifier: "en")))
        for name in ["Apache", "Ping Island", "Silkscreen", "Sparkle"] {
            XCTAssertTrue(text.contains(name), "Missing \(name)")
        }
    }

    func testUnconfiguredAndPlaceholderLinksAreUnavailable() {
        XCTAssertNil(MacIslandDistributionLinks(info: [:]).website)
        for value in [
            "$(MAC_ISLAND_WEBSITE_URL)", "http://product.test", "https://example.com", "https://product.invalid",
            "https://name:secret@product.test",
        ] {
            XCTAssertNil(MacIslandDistributionLinks(info: ["MacIslandWebsiteURL": value]).website)
        }
    }

    func testConfiguredHTTPSLinkIsKeptWithoutAttachingUserMetadata() {
        let value = "https://product.test/downloads"
        XCTAssertEqual(MacIslandDistributionLinks(info: ["MacIslandWebsiteURL": value]).website?.absoluteString, value)
    }
}
