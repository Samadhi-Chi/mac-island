import Foundation

/// Fixed before shared stores initialize; test/fixture launches cannot touch live clients.
nonisolated enum MacIslandRuntimeEnvironment {
    static let allowsLiveIO = allowsLiveIO(
        environment: Foundation.ProcessInfo.processInfo.environment,
        hasXCTestRuntime: NSClassFromString("XCTestCase") != nil
    )

    static func allowsLiveIO(environment: [String: String], hasXCTestRuntime: Bool) -> Bool {
        !hasXCTestRuntime && environment["XCTestConfigurationFilePath"] == nil
            && environment["PING_ISLAND_UI_TEST_MODE"] != "1"
            && environment["MAC_ISLAND_UI_TEST_MODE"] != "1"
            && (environment["MAC_ISLAND_FIXTURE_PATH"] ?? "").isEmpty
            && (environment["PING_ISLAND_FIXTURE_PATH"] ?? "").isEmpty
    }

    private static let defaults: UserDefaults =
        allowsLiveIO ? .standard : MacIslandEphemeralDefaults(suiteName: "MacIsland.Isolated")!

    static func makeDefaults() -> UserDefaults { defaults }
}

/// UserDefaults-compatible storage with no persistent domain writes.
nonisolated final class MacIslandEphemeralDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    override func object(forKey key: String) -> Any? { lock.withLock { values[key] } }
    override func set(_ value: Any?, forKey key: String) { lock.withLock { values[key] = value } }
    override func removeObject(forKey key: String) { lock.withLock { _ = values.removeValue(forKey: key) } }
    override func dictionaryRepresentation() -> [String: Any] { lock.withLock { values } }
    override func register(defaults: [String: Any]) {
        lock.withLock { values.merge(defaults) { existing, _ in existing } }
    }
    override func bool(forKey key: String) -> Bool { (object(forKey: key) as? NSNumber)?.boolValue ?? false }
    override func integer(forKey key: String) -> Int { (object(forKey: key) as? NSNumber)?.intValue ?? 0 }
    override func double(forKey key: String) -> Double { (object(forKey: key) as? NSNumber)?.doubleValue ?? 0 }
    override func float(forKey key: String) -> Float { (object(forKey: key) as? NSNumber)?.floatValue ?? 0 }
    override func string(forKey key: String) -> String? { object(forKey: key) as? String }
    override func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    override func array(forKey key: String) -> [Any]? { object(forKey: key) as? [Any] }
    override func dictionary(forKey key: String) -> [String: Any]? { object(forKey: key) as? [String: Any] }
    override func stringArray(forKey key: String) -> [String]? { object(forKey: key) as? [String] }
    override func set(_ value: Bool, forKey key: String) { set(NSNumber(value: value), forKey: key) }
    override func set(_ value: Int, forKey key: String) { set(NSNumber(value: value), forKey: key) }
    override func set(_ value: Double, forKey key: String) { set(NSNumber(value: value), forKey: key) }
    override func set(_ value: Float, forKey key: String) { set(NSNumber(value: value), forKey: key) }
}
