import Foundation

public enum DurationFormatting {
    public static func compactCountdown(remaining: TimeInterval) -> String? {
        guard remaining > 0 else { return nil }
        let seconds = Int(remaining.rounded(.up))
        let minutesPart = seconds / 60
        let secondsPart = seconds % 60
        if minutesPart > 0 {
            return "\(minutesPart)m \(secondsPart)s"
        }
        return "\(secondsPart)s"
    }

    public static func compactCountdown(endsAt: Date, relativeTo now: Date = .now) -> String? {
        compactCountdown(remaining: max(0, endsAt.timeIntervalSince(now)))
    }
}
