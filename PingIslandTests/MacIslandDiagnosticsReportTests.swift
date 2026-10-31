import XCTest

@testable import Ping_Island

@MainActor
final class MacIslandDiagnosticsReportTests: XCTestCase {
    func testReportUsesFixedFieldsAndRejectsUnexpectedVersionText() throws {
        let report = MacIslandDiagnosticsReport(
            appVersion: "1.0.0", appBuild: "/private/project-secret",
            systemVersion: .init(majorVersion: 15, minorVersion: 0, patchVersion: 1),
            codex: .init(phase: .retrying, failure: .connectionLost),
            personalAgents: [.muse: .init(phase: .readFailed, version: "secret-session-title")],
            enabled: [.muse]
        )
        let data = try report.data()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            Set(object.keys), ["schemaVersion", "appVersion", "macOSVersion", "codexPhase", "codexFailure", "sources"])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("/private"))
        XCTAssertEqual(
            report.sources.first(where: { $0.client == PersonalAgentClient.muse.rawValue })?.phase, "readFailed")
    }

    func testArchiveContainsOnlyTheContentFreeReport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = MacIslandDiagnosticsReport(
            appVersion: "1.0", appBuild: "1", systemVersion: .init(majorVersion: 15, minorVersion: 0, patchVersion: 0),
            codex: .init(), personalAgents: [:], enabled: [])
        let result = try await DiagnosticsExporter.shared.exportContentFreeArchive(
            report: report, to: directory.appendingPathComponent("diagnostics"))
        XCTAssertEqual(result.archiveURL.pathExtension, "zip")
        let extracted = directory.appendingPathComponent("extracted")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", result.archiveURL.path, extracted.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let root = extracted.appendingPathComponent("MacIsland-Diagnostics")
        XCTAssertEqual(
            Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["health.json", "README.txt"])
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("health.json")), try report.data())
    }
}
