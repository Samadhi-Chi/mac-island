import Foundation

struct CursorUsageSnapshot: Equatable, Codable, Sendable {
    let capturedAt: Date
    let planName: String?
    let billingCycleEnd: Date?
    let totalSpendCents: Int?
    let includedSpendCents: Int?
    let bonusSpendCents: Int?
    let limitCents: Int?
    let totalUsedPercentage: Double?
    let apiUsedPercentage: Double?
    let autoUsedPercentage: Double?

    nonisolated var isEmpty: Bool {
        totalUsedPercentage == nil
            && apiUsedPercentage == nil
            && autoUsedPercentage == nil
    }
}

enum CursorUsageLoaderError: Error, Equatable {
    case networkDisabled
    case credentialsUnavailable
    case invalidEndpoint
    case invalidResponse
    case httpStatus(Int)
}

enum CursorUsageLoader {
    nonisolated static let defaultEndpoint = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
    )!

    nonisolated static func load(
        databaseURL: URL = CursorLocalAccountAuthorizationReader.defaultDatabaseURL,
        endpoint: URL = defaultEndpoint,
        session: URLSession = CursorUsageURLSession.shared,
        now: Date = Date()
    ) async throws -> CursorUsageSnapshot? {
        guard !MacIslandProductPolicy.monitorOnly, MacIslandRuntimeEnvironment.allowsLiveIO else {
            throw CursorUsageLoaderError.networkDisabled
        }
        guard endpoint.scheme == "https",
            endpoint.host == "api2.cursor.sh"
        else {
            throw CursorUsageLoaderError.invalidEndpoint
        }
        guard
            let authorization = CursorLocalAccountAuthorizationReader.read(
                databaseURL: databaseURL
            )
        else {
            throw CursorUsageLoaderError.credentialsUnavailable
        }

        let request = try makeRequest(
            endpoint: endpoint,
            accessToken: authorization.accessToken
        )
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw CursorUsageLoaderError.invalidResponse
        }
        guard response.statusCode == 200 else {
            throw CursorUsageLoaderError.httpStatus(response.statusCode)
        }

        return try snapshot(
            from: data,
            planName: authorization.planName,
            capturedAt: now
        )
    }

    nonisolated static func makeRequest(
        endpoint: URL = defaultEndpoint,
        accessToken: String
    ) throws -> URLRequest {
        guard endpoint.scheme == "https",
            endpoint.host == "api2.cursor.sh",
            !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CursorUsageLoaderError.invalidEndpoint
        }

        var request = URLRequest(
            url: endpoint,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 12
        )
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    nonisolated static func snapshot(
        from data: Data,
        planName: String?,
        capturedAt: Date = Date()
    ) throws -> CursorUsageSnapshot? {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CursorUsageLoaderError.invalidResponse
        }
        guard bool(from: payload["enabled"]) != false,
            let planUsage = payload["planUsage"] as? [String: Any]
        else {
            return nil
        }

        let limitCents = integer(from: planUsage["limit"])
        let includedSpendCents = integer(from: planUsage["includedSpend"])
        let totalUsedPercentage =
            percentage(from: planUsage["totalPercentUsed"])
            ?? derivedPercentage(used: includedSpendCents, limit: limitCents)
        let snapshot = CursorUsageSnapshot(
            capturedAt: capturedAt,
            planName: normalizedPlanName(planName),
            billingCycleEnd: dateFromMilliseconds(payload["billingCycleEnd"]),
            totalSpendCents: integer(from: planUsage["totalSpend"]),
            includedSpendCents: includedSpendCents,
            bonusSpendCents: integer(from: planUsage["bonusSpend"]),
            limitCents: limitCents,
            totalUsedPercentage: totalUsedPercentage,
            apiUsedPercentage: percentage(from: planUsage["apiPercentUsed"]),
            autoUsedPercentage: percentage(from: planUsage["autoPercentUsed"])
        )
        return snapshot.isEmpty ? nil : snapshot
    }

    private nonisolated static func normalizedPlanName(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        switch value.lowercased() {
        case "pro": return "Pro"
        case "pro_plus", "pro-plus", "proplus": return "Pro+"
        case "ultra": return "Ultra"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        default: return value
        }
    }

    private nonisolated static func derivedPercentage(used: Int?, limit: Int?) -> Double? {
        guard let used, let limit, limit > 0 else { return nil }
        return ObservedNumber.percentage(Double(used) / Double(limit) * 100)
    }

    private nonisolated static func percentage(from value: Any?) -> Double? {
        guard let value = number(from: value), value.isFinite else { return nil }
        return ObservedNumber.percentage(value)
    }

    private nonisolated static func integer(from value: Any?) -> Int? {
        ObservedNumber.integer(value)
    }

    private nonisolated static func number(from value: Any?) -> Double? {
        ObservedNumber.double(value)
    }

    private nonisolated static func bool(from value: Any?) -> Bool? {
        switch value {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            return ["true", "1"].contains(value.lowercased())
        default:
            return nil
        }
    }

    private nonisolated static func dateFromMilliseconds(_ value: Any?) -> Date? {
        guard let milliseconds = number(from: value),
            milliseconds > 0
        else {
            return nil
        }
        return ObservedNumber.unixDate(milliseconds / 1_000)
    }
}

enum CursorUsageURLSession {
    nonisolated static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }()
}
