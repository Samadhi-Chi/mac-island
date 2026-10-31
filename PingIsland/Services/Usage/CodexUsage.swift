import Foundation

extension Notification.Name {
    static let macIslandCodexUsageDidUpdate = Notification.Name("MacIslandCodexUsageDidUpdate")
}

struct CodexUsageWindow: Equatable, Codable, Sendable, Identifiable {
    let key: String
    let label: String
    let usedPercentage: Double
    let leftPercentage: Double
    let windowMinutes: Int
    let resetsAt: Date?

    var id: String { key }

    var roundedUsedPercentage: Int {
        ObservedNumber.roundedDisplay(usedPercentage)
    }
}

struct CodexUsageSnapshot: Equatable, Codable, Sendable {
    let sourceFilePath: String
    let capturedAt: Date?
    let planType: String?
    let limitID: String?
    let tokenUsage: CodexTokenUsage?
    let windows: [CodexUsageWindow]

    nonisolated init(
        sourceFilePath: String,
        capturedAt: Date?,
        planType: String?,
        limitID: String?,
        tokenUsage: CodexTokenUsage? = nil,
        windows: [CodexUsageWindow]
    ) {
        self.sourceFilePath = sourceFilePath
        self.capturedAt = capturedAt
        self.planType = planType
        self.limitID = limitID
        self.tokenUsage = tokenUsage
        self.windows = windows
    }

    private enum CodingKeys: String, CodingKey {
        case sourceFilePath
        case capturedAt
        case planType
        case limitID
        case tokenUsage
        case windows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceFilePath = try container.decode(String.self, forKey: .sourceFilePath)
        capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        limitID = try container.decodeIfPresent(String.self, forKey: .limitID)
        tokenUsage = try container.decodeIfPresent(CodexTokenUsage.self, forKey: .tokenUsage)
        windows = try container.decode([CodexUsageWindow].self, forKey: .windows)
    }

    nonisolated var threadID: String? {
        let stem = URL(fileURLWithPath: sourceFilePath).deletingPathExtension().lastPathComponent
        guard stem.count >= 36 else { return nil }

        let candidate = String(stem.suffix(36)).lowercased()
        return UUID(uuidString: candidate) == nil ? nil : candidate
    }

    nonisolated
        var isEmpty: Bool
    {
        windows.isEmpty
    }

    /// Persist and publish only the quota fields required by Mac Island. Raw
    /// transcript paths, token totals, plan metadata, and limit identifiers are
    /// deliberately discarded at the usage boundary.
    nonisolated var quotaOnlyProjection: CodexUsageSnapshot {
        CodexUsageSnapshot(
            sourceFilePath: "",
            capturedAt: capturedAt,
            planType: nil,
            limitID: nil,
            tokenUsage: nil,
            windows: windows
        )
    }
}

enum CodexUsageLoader {
    nonisolated static let defaultRootURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)

    private nonisolated static let defaultCandidateScanLimit = 24
    private nonisolated static let defaultMaxBytesPerFile = 4 * 1024 * 1024
    private nonisolated static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedResult: CachedResult?

    private struct Candidate {
        let fileURL: URL
        let modifiedAt: Date
        let fileSize: UInt64
    }

    private struct CachedResult {
        let fingerprint: String
        let snapshot: CodexUsageSnapshot?
    }

    nonisolated static func load(
        fromRootURL rootURL: URL = defaultRootURL,
        fileManager: FileManager = .default,
        candidateScanLimit: Int = defaultCandidateScanLimit,
        maxBytesPerFile: Int = defaultMaxBytesPerFile
    ) throws -> CodexUsageSnapshot? {
        guard fileManager.fileExists(atPath: rootURL.path),
            let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return nil
        }

        var candidates: [Candidate] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasPrefix("rollout-"),
                fileURL.pathExtension == "jsonl",
                let resourceValues = try? fileURL.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
                ),
                resourceValues.isRegularFile == true
            else {
                continue
            }

            candidates.append(
                Candidate(
                    fileURL: fileURL,
                    modifiedAt: resourceValues.contentModificationDate ?? .distantPast,
                    fileSize: UInt64(max(0, resourceValues.fileSize ?? 0))
                )
            )
        }

        let sortedCandidates = candidates.sorted { lhs, rhs in
            if lhs.modifiedAt == rhs.modifiedAt {
                return lhs.fileURL.path.localizedStandardCompare(rhs.fileURL.path) == .orderedDescending
            }
            return lhs.modifiedAt > rhs.modifiedAt
        }

        let limitedCandidates = Array(sortedCandidates.prefix(max(1, candidateScanLimit)))
        let fingerprint = cacheFingerprint(
            rootURL: rootURL,
            candidates: limitedCandidates,
            candidateScanLimit: candidateScanLimit,
            maxBytesPerFile: maxBytesPerFile
        )
        if let cached = cachedSnapshot(for: fingerprint) {
            return cached
        }

        var bestSnapshot: CodexUsageSnapshot?
        var bestCapturedAt: Date = .distantPast

        for candidate in limitedCandidates {
            guard
                let snapshot = loadLatestSnapshot(
                    from: candidate.fileURL,
                    modifiedAt: candidate.modifiedAt,
                    fileSize: candidate.fileSize,
                    maxBytes: maxBytesPerFile
                )
            else {
                continue
            }
            let capturedAt = snapshot.capturedAt ?? candidate.modifiedAt
            if capturedAt > bestCapturedAt {
                bestSnapshot = snapshot
                bestCapturedAt = capturedAt
            }
        }

        cache(snapshot: bestSnapshot, for: fingerprint)
        return bestSnapshot
    }

    /// Parses the read-only `account/rateLimits/read` response. The app-server
    /// returns both a legacy single bucket and a multi-bucket map. Always prefer
    /// the main `codex` bucket so model-specific allowances (for example
    /// `codex_bengalfox`) cannot masquerade as the account's primary quota.
    nonisolated static func snapshotFromAppServerResponse(
        _ response: [String: Any],
        capturedAt: Date = Date()
    ) -> CodexUsageSnapshot? {
        if let buckets = response["rateLimitsByLimitId"] as? [String: Any],
            let mainBucket = buckets.first(where: { key, _ in
                key.caseInsensitiveCompare("codex") == .orderedSame
            })?.value as? [String: Any],
            let snapshot = snapshotFromAppServerRateLimits(mainBucket, capturedAt: capturedAt)
        {
            return snapshot
        }

        guard let legacyBucket = response["rateLimits"] as? [String: Any] else {
            return nil
        }
        return snapshotFromAppServerRateLimits(legacyBucket, capturedAt: capturedAt)
    }

    nonisolated static func snapshotFromAppServerRateLimits(
        _ rateLimits: [String: Any],
        capturedAt: Date = Date()
    ) -> CodexUsageSnapshot? {
        let limitID =
            string(from: rateLimits["limitId"])
            ?? string(from: rateLimits["limit_id"])
        let windows = [
            ("primary", rateLimits["primary"]),
            ("secondary", rateLimits["secondary"]),
        ].compactMap { key, payload -> CodexUsageWindow? in
            guard let payload = payload as? [String: Any],
                let usedPercentage = ObservedNumber.percentage(payload["usedPercent"])
                    ?? ObservedNumber.percentage(payload["used_percent"]),
                let windowMinutes = integer(from: payload["windowDurationMins"])
                    ?? integer(from: payload["window_minutes"])
            else {
                return nil
            }

            return CodexUsageWindow(
                key: key,
                label: windowLabel(forMinutes: windowMinutes),
                usedPercentage: usedPercentage,
                leftPercentage: max(0, 100 - usedPercentage),
                windowMinutes: windowMinutes,
                resetsAt: date(from: payload["resetsAt"] ?? payload["resets_at"])
            )
        }
        guard !windows.isEmpty else { return nil }

        return CodexUsageSnapshot(
            sourceFilePath: "",
            capturedAt: capturedAt,
            planType: string(from: rateLimits["planType"])
                ?? string(from: rateLimits["plan_type"]),
            limitID: limitID,
            tokenUsage: nil,
            windows: windows
        )
    }

    nonisolated static func isMainCodexLimit(_ snapshot: CodexUsageSnapshot) -> Bool {
        guard let limitID = snapshot.limitID?.trimmingCharacters(in: .whitespacesAndNewlines),
            !limitID.isEmpty
        else {
            return true
        }
        return limitID.caseInsensitiveCompare("codex") == .orderedSame
    }

    private nonisolated static func loadLatestSnapshot(
        from fileURL: URL,
        modifiedAt: Date,
        fileSize: UInt64,
        maxBytes: Int
    ) -> CodexUsageSnapshot? {
        guard fileSize > 0,
            maxBytes > 0,
            let contents = readSuffixText(from: fileURL, fileSize: fileSize, maxBytes: maxBytes)
        else {
            return nil
        }

        for line in contents.split(separator: "\n", omittingEmptySubsequences: false).reversed() {
            if line.contains("\"token_count\""),
                line.contains("\"rate_limits\""),
                let snapshot = snapshot(from: String(line), filePath: fileURL.path, fallbackTimestamp: modifiedAt)
            {
                return snapshot
            }
        }
        return nil
    }

    private nonisolated static func readSuffixText(from fileURL: URL, fileSize: UInt64, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }

        let readSize = min(fileSize, UInt64(maxBytes))
        let offset = fileSize - readSize
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: Int(readSize)) else {
                return nil
            }

            var text = String(decoding: data, as: UTF8.self)
            if offset > 0, let newlineIndex = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: newlineIndex)...])
            }
            return text
        } catch {
            return nil
        }
    }

    private nonisolated static func cachedSnapshot(for fingerprint: String) -> CodexUsageSnapshot?? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let cachedResult, cachedResult.fingerprint == fingerprint else {
            return nil
        }
        return cachedResult.snapshot
    }

    private nonisolated static func cache(snapshot: CodexUsageSnapshot?, for fingerprint: String) {
        cacheLock.lock()
        cachedResult = CachedResult(fingerprint: fingerprint, snapshot: snapshot)
        cacheLock.unlock()
    }

    private nonisolated static func cacheFingerprint(
        rootURL: URL,
        candidates: [Candidate],
        candidateScanLimit: Int,
        maxBytesPerFile: Int
    ) -> String {
        var parts = [
            rootURL.resolvingSymlinksInPath().path,
            "limit=\(candidateScanLimit)",
            "bytes=\(maxBytesPerFile)",
        ]
        parts.reserveCapacity(candidates.count + 1)
        for candidate in candidates {
            parts.append(
                [
                    candidate.fileURL.resolvingSymlinksInPath().path,
                    String(candidate.modifiedAt.timeIntervalSinceReferenceDate),
                    String(candidate.fileSize),
                ].joined(separator: "|"))
        }
        return parts.joined(separator: "\n")
    }

    private nonisolated static func snapshot(from line: String, filePath: String, fallbackTimestamp: Date)
        -> CodexUsageSnapshot?
    {
        guard let object = jsonObject(for: line),
            object["type"] as? String == "event_msg"
        else {
            return nil
        }

        let payload = object["payload"] as? [String: Any] ?? [:]
        guard payload["type"] as? String == "token_count",
            let rateLimits = payload["rate_limits"] as? [String: Any]
        else {
            return nil
        }

        let windows = ["primary", "secondary"].compactMap { key in
            usageWindow(for: key, in: rateLimits)
        }
        guard !windows.isEmpty else {
            return nil
        }

        return CodexUsageSnapshot(
            sourceFilePath: filePath,
            capturedAt: timestamp(from: object["timestamp"]) ?? fallbackTimestamp,
            planType: string(from: rateLimits["plan_type"]),
            limitID: string(from: rateLimits["limit_id"]),
            tokenUsage: tokenUsage(from: payload["info"]),
            windows: windows
        )
    }

    private nonisolated static func usageWindow(for key: String, in rateLimits: [String: Any]) -> CodexUsageWindow? {
        guard let payload = rateLimits[key] as? [String: Any],
            let usedPercentage = ObservedNumber.percentage(payload["used_percent"]),
            let windowMinutes = integer(from: payload["window_minutes"])
        else {
            return nil
        }

        return CodexUsageWindow(
            key: key,
            label: windowLabel(forMinutes: windowMinutes),
            usedPercentage: usedPercentage,
            leftPercentage: max(0, 100 - usedPercentage),
            windowMinutes: windowMinutes,
            resetsAt: date(from: payload["resets_at"])
        )
    }

    private nonisolated static func windowLabel(forMinutes minutes: Int) -> String {
        let days = minutes / 1_440
        let remainingMinutesAfterDays = minutes % 1_440
        let hours = remainingMinutesAfterDays / 60
        let remainingMinutes = remainingMinutesAfterDays % 60

        if days > 0, hours == 0, remainingMinutes == 0 {
            return "\(days)d"
        }
        if days > 0, hours > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0, remainingMinutes == 0 {
            return "\(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(minutes)m"
    }

    private nonisolated static func jsonObject(for line: String) -> [String: Any]? {
        guard !line.isEmpty else {
            return nil
        }

        let data = Data(line.utf8)
        guard let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            return nil
        }
        return dictionary
    }

    private nonisolated static func timestamp(from value: Any?) -> Date? {
        guard let string = value as? String else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    private nonisolated static func number(from value: Any?) -> Double? {
        ObservedNumber.double(value)
    }

    private nonisolated static func integer(from value: Any?) -> Int? {
        ObservedNumber.integer(value)
    }

    private nonisolated static func date(from value: Any?) -> Date? {
        switch value {
        case let number as NSNumber:
            return ObservedNumber.unixDate(number.doubleValue)
        case let string as String:
            guard let seconds = Double(string) else {
                return nil
            }
            return ObservedNumber.unixDate(seconds)
        default:
            return nil
        }
    }

    private nonisolated static func string(from value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.isEmpty ? nil : string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private nonisolated static func tokenUsage(from value: Any?) -> CodexTokenUsage? {
        let usage: [String: Any]?
        if let info = value as? [String: Any] {
            usage = info["total_token_usage"] as? [String: Any]
        } else {
            usage = nil
        }

        guard let usage else {
            return nil
        }

        let inputTokens =
            integer(from: usage["input_tokens"])
            ?? integer(from: usage["prompt_tokens"])
            ?? 0
        let outputTokens =
            integer(from: usage["output_tokens"])
            ?? integer(from: usage["completion_tokens"])
            ?? 0
        let totalTokens =
            integer(from: usage["total_tokens"])
            ?? ObservedNumber.sum(inputTokens, outputTokens)

        guard inputTokens > 0 || outputTokens > 0 || totalTokens > 0 else {
            return nil
        }

        return CodexTokenUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens
        )
    }
}
