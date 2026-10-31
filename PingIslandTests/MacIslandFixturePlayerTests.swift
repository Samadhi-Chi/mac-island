import XCTest

@testable import Ping_Island

final class MacIslandFixturePlayerTests: XCTestCase {
    func testPersonalAgentFixtureCountsBotsInsteadOfActivities() throws {
        let fixtureURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        try Data(
            #"{"schemaVersion":1,"events":[],"personalAgents":[{"client":"muse","agentName":"Example Muse","activityLabels":["Example task Result 10:12 am","Example task Result 10:12 am"]},{"client":"grokBot","agentName":"Example Bot"}]}"#
                .utf8
        ).write(to: fixtureURL)
        let observations = try MacIslandFixturePlayer.personalAgentObservations(fileURL: fixtureURL)
        XCTAssertEqual(observations.count, 2)
        XCTAssertEqual(observations.map(\.agentName), ["Example Muse", "Example Bot"])
        XCTAssertEqual(observations[0].nativeActivityLabels.count, 2)
        XCTAssertEqual(observations[1].nativeActivityLabels, [])
        XCTAssertEqual(Set(observations.map(\.id)).count, 2)
    }

    func testStoredNativeTitleAndActivityAreKeptSeparateFromDirectoryAndPrompt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtureURL = directory.appendingPathComponent("fixture.json")
        try Data(
            #"{"schemaVersion":1,"storedCodexThreads":[{"sessionId":"fixture-stored-title","workspace":"/tmp/example-workspace","nativeTitle":"Original title","activitySecondsAgo":3600}],"events":[]}"#
                .utf8
        )
        .write(to: fixtureURL)
        await SessionStore.shared.process(.sessionArchived(sessionId: "fixture-stored-title"))
        try await MacIslandFixturePlayer.play(fileURL: fixtureURL)
        let session = await SessionStore.shared.session(for: "fixture-stored-title")
        XCTAssertEqual(session?.sessionName, "Original title")
        XCTAssertEqual(session?.projectName, "example-workspace")
        XCTAssertNil(session?.conversationInfo.firstUserMessage)
        XCTAssertTrue(session?.shouldAutoArchiveFromPrimaryUI == true)
        await SessionStore.shared.process(.sessionArchived(sessionId: "fixture-stored-title"))
    }

    func testUnknownSchemaIsRejectedBeforeEventsAreApplied() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fixtureURL = directory.appendingPathComponent("fixture.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"schemaVersion":2,"events":[]}"#.utf8).write(to: fixtureURL)

        do {
            try await MacIslandFixturePlayer.play(fileURL: fixtureURL)
            XCTFail("Expected unsupported schema to fail")
        } catch MacIslandFixturePlayer.FixtureError.unsupportedSchema(let version) {
            XCTAssertEqual(version, 2)
        }
    }

    func testUnsupportedClientIsRejected() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fixtureURL = directory.appendingPathComponent("fixture.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(
            #"{"schemaVersion":1,"events":[{"sessionId":"unsupported","client":"other-agent","workspace":"/tmp","event":"Start","status":"processing"}]}"#
                .utf8
        ).write(to: fixtureURL)

        do {
            try await MacIslandFixturePlayer.play(fileURL: fixtureURL)
            XCTFail("Expected unsupported client to fail")
        } catch MacIslandFixturePlayer.FixtureError.unsupportedClient(let client) {
            XCTAssertEqual(client, "other-agent")
        }
    }
}
