import Foundation

enum BenchmarkTimestampFormatting {
    static func formattedGeneratedAt(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "Unknown"
        }
        guard let date = parsedGeneratedAt(value) else {
            return value
        }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    static func parsedGeneratedAt(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: value)
    }
}
