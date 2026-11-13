import SwiftUI

public enum Theme {
    public static let accent = Color(red: 0.62, green: 0.36, blue: 0.95)
    public static let live = Color.red

    public static func platformColor(for platform: StreamPlatform) -> Color {
        switch platform {
        case .youtube:
            return Color.red
        case .twitch:
            return Color(red: 0.569, green: 0.275, blue: 1.0)
        }
    }
}
