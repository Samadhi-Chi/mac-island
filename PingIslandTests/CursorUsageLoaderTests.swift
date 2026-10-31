import XCTest

@testable import Ping_Island

final class CursorUsageLoaderTests: XCTestCase {
    func testParsesCurrentPeriodUsageWithoutInventingQuota() throws {
        let data = try XCTUnwrap(
            """
            {
              "enabled": true,
              "billingCycleEnd": "1787199156000",
              "planUsage": {
                "totalSpend": 8007,
                "includedSpend": 2000,
                "bonusSpend": 6007,
                "limit": 2000,
                "autoPercentUsed": 10.07,
                "apiPercentUsed": 100,
                "totalPercentUsed": 23.208695652173912
              }
            }
            """.data(using: .utf8)
        )
        let capturedAt = Date(timeIntervalSince1970: 1_775_000_000)

        let snapshot = try XCTUnwrap(
            CursorUsageLoader.snapshot(
                from: data,
                planName: "pro",
                capturedAt: capturedAt
            )
        )

        XCTAssertEqual(snapshot.planName, "Pro")
        XCTAssertEqual(snapshot.capturedAt, capturedAt)
        XCTAssertEqual(snapshot.billingCycleEnd, Date(timeIntervalSince1970: 1_787_199_156))
        XCTAssertEqual(snapshot.totalSpendCents, 8_007)
        XCTAssertEqual(snapshot.includedSpendCents, 2_000)
        XCTAssertEqual(snapshot.bonusSpendCents, 6_007)
        XCTAssertEqual(snapshot.limitCents, 2_000)
        XCTAssertEqual(snapshot.totalUsedPercentage ?? -1, 23.208695652173912, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.apiUsedPercentage, 100)
        XCTAssertEqual(snapshot.autoUsedPercentage ?? -1, 10.07, accuracy: 0.000_001)
    }

    func testDisabledUsageReturnsNil() throws {
        let data = try XCTUnwrap(
            """
            {"enabled":false,"planUsage":{"totalPercentUsed":12}}
            """.data(using: .utf8)
        )

        XCTAssertNil(try CursorUsageLoader.snapshot(from: data, planName: "pro"))
    }

    func testRequestIsPinnedToCursorHTTPSAndKeepsTokenOutOfBody() throws {
        let request = try CursorUsageLoader.makeRequest(accessToken: "local-secret")

        XCTAssertEqual(request.url, CursorUsageLoader.defaultEndpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Connect-Protocol-Version"), "1")
        XCTAssertEqual(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8), "{}")
        XCTAssertFalse(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)?.contains("local-secret") == true)

        XCTAssertThrowsError(
            try CursorUsageLoader.makeRequest(
                endpoint: URL(string: "https://example.com/usage")!,
                accessToken: "local-secret"
            )
        ) { error in
            XCTAssertEqual(error as? CursorUsageLoaderError, .invalidEndpoint)
        }
    }
}
