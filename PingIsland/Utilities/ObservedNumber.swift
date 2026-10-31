import Foundation

/// Numbers from local clients are still untrusted; never convert a Double with Int(_:).
nonisolated enum ObservedNumber {
    static func double(_ value: Any?) -> Double? {
        let number: Double?
        switch value {
        case let value as NSNumber: number = value.doubleValue
        case let value as String: number = Double(value)
        default: number = nil
        }
        guard let number, number.isFinite else { return nil }
        return number
    }

    static func integer(_ value: Any?) -> Int? {
        if let value = value as? String { return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard let number = double(value) else { return nil }
        return Int(exactly: number)
    }

    static func percentage(_ value: Any?) -> Double? {
        // Permit documented overage without accepting arbitrary numeric magnitudes.
        guard let number = double(value), (0...10_000).contains(number) else { return nil }
        return number
    }

    static func unixDate(_ value: Any?) -> Date? {
        guard let seconds = double(value), (-62_135_596_800...253_402_300_799).contains(seconds) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func roundedDisplay(_ value: Double) -> Int {
        Int(exactly: value.rounded()) ?? 0
    }

    static func sum(_ lhs: Int, _ rhs: Int) -> Int {
        let result = max(0, lhs).addingReportingOverflow(max(0, rhs))
        return result.overflow ? .max : result.partialValue
    }
}
