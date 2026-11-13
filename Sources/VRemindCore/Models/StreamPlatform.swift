import Foundation

public enum StreamPlatform: String, Codable, CaseIterable, Sendable, Hashable {
    case youtube
    case twitch

    public var displayName: String {
        switch self {
        case .youtube:
            return "YouTube"
        case .twitch:
            return "Twitch"
        }
    }
}
