import Foundation

public enum ElapsedTime {
    /// Compact elapsed time, truncated to whole units: "42m", "2h 05m", "3d 4h".
    /// Negative intervals clamp to "0m".
    public static func short(from start: Date, to end: Date) -> String {
        let totalMinutes = max(0, Int(end.timeIntervalSince(start) / 60))
        let minutes = totalMinutes % 60
        let totalHours = totalMinutes / 60
        if totalHours == 0 {
            return "\(minutes)m"
        }
        if totalHours < 24 {
            return String(format: "%dh %02dm", totalHours, minutes)
        }
        return "\(totalHours / 24)d \(totalHours % 24)h"
    }
}
