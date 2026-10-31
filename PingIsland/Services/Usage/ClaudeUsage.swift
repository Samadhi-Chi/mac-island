import Foundation

struct ClaudeUsageWindow: Equatable, Codable, Sendable {
    let usedPercentage: Double
    let resetsAt: Date?

    var roundedUsedPercentage: Int {
        ObservedNumber.roundedDisplay(usedPercentage)
    }
}

struct ClaudeUsageSnapshot: Equatable, Codable, Sendable {
    let fiveHour: ClaudeUsageWindow?
    let sevenDay: ClaudeUsageWindow?
    let cachedAt: Date?

    nonisolated
        var isEmpty: Bool
    {
        let hasFiveHour: Bool = if case .some = fiveHour { true } else { false }
        let hasSevenDay: Bool = if case .some = sevenDay { true } else { false }
        return !hasFiveHour && !hasSevenDay
    }

    nonisolated func isFresh(
        now: Date = Date(),
        maximumAge: TimeInterval = ClaudeUsageLoader.maximumCacheAge
    ) -> Bool {
        guard let cachedAt else { return false }
        let age = now.timeIntervalSince(cachedAt)
        return age >= 0 && age <= maximumAge
    }
}

enum ClaudeUsageLoader {
    nonisolated static let maximumCacheAge: TimeInterval = 15 * 60
    nonisolated static var defaultCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mac-island", isDirectory: true)
            .appendingPathComponent("run", isDirectory: true)
            .appendingPathComponent("claude-rate-limits.json")
    }

    nonisolated static func load(
        from url: URL = defaultCacheURL,
        now: Date = Date()
    ) throws -> ClaudeUsageSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else {
            return nil
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let cachedAt = attributes?[.modificationDate] as? Date
        let snapshot = ClaudeUsageSnapshot(
            fiveHour: usageWindow(for: "five_hour", in: payload),
            sevenDay: usageWindow(for: "seven_day", in: payload),
            cachedAt: cachedAt
        )

        return snapshot.isEmpty || !snapshot.isFresh(now: now) ? nil : snapshot
    }

    private nonisolated static func usageWindow(for key: String, in payload: [String: Any]) -> ClaudeUsageWindow? {
        guard let window = payload[key] as? [String: Any],
            let rawPercentage = ObservedNumber.percentage(window["used_percentage"])
                ?? ObservedNumber.percentage(window["utilization"])
        else {
            return nil
        }

        return ClaudeUsageWindow(
            usedPercentage: rawPercentage,
            resetsAt: date(from: window["resets_at"])
        )
    }

    private nonisolated static func number(from value: Any?) -> Double? {
        ObservedNumber.double(value)
    }

    private nonisolated static func date(from value: Any?) -> Date? {
        switch value {
        case let value as NSNumber:
            return ObservedNumber.unixDate(value.doubleValue)
        case let value as String:
            if let seconds = Double(value) {
                return ObservedNumber.unixDate(seconds)
            }

            let formatterWithFractionalSeconds = ISO8601DateFormatter()
            formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatterWithFractionalSeconds.date(from: value) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        default:
            return nil
        }
    }
}
