import Foundation

/// A deliberately small, typed export. Never accept raw settings, session
/// objects, filenames, error descriptions, logs or conversation text here.
nonisolated struct MacIslandDiagnosticsReport: Codable, Equatable, Sendable {
    struct Source: Codable, Equatable, Sendable {
        let client: String
        let enabled: Bool
        let phase: String
        let version: String?
    }

    let schemaVersion: Int
    let appVersion: String?
    let appBuild: String?
    let macOSVersion: String
    let codexPhase: String
    let codexFailure: String?
    let sources: [Source]

    init(
        appVersion: String?, appBuild: String?, systemVersion: OperatingSystemVersion,
        codex: CodexMonitorHealth, personalAgents: [PersonalAgentClient: PersonalAgentHealth],
        enabled: Set<PersonalAgentClient>
    ) {
        schemaVersion = 1
        self.appVersion = Self.numericVersion(appVersion)
        self.appBuild = Self.numericVersion(appBuild)
        macOSVersion = "\(systemVersion.majorVersion).\(systemVersion.minorVersion).\(systemVersion.patchVersion)"
        codexPhase = codex.phase.rawValue
        codexFailure = codex.failure?.rawValue
        sources = PersonalAgentClient.allCases.map { client in
            Source(
                client: client.rawValue, enabled: enabled.contains(client),
                phase: (personalAgents[client]?.phase ?? .disabled).rawValue,
                version: Self.numericVersion(personalAgents[client]?.version))
        }
    }

    private static func numericVersion(_ value: String?) -> String? {
        guard let value, value.count <= 40,
            value.range(of: #"^[0-9]+(?:\.[0-9]+){0,4}$"#, options: .regularExpression) != nil
        else { return nil }
        return value
    }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
