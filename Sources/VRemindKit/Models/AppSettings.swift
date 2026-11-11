import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var launchAtLogin: Bool
    public var notifyOnLive: Bool
    public var notifyOnUpcoming: Bool
    public var playNotificationSound: Bool
    public var hasCompletedOnboarding: Bool

    public init(
        launchAtLogin: Bool = false,
        notifyOnLive: Bool = true,
        notifyOnUpcoming: Bool = false,
        playNotificationSound: Bool = true,
        hasCompletedOnboarding: Bool = false
    ) {
        self.launchAtLogin = launchAtLogin
        self.notifyOnLive = notifyOnLive
        self.notifyOnUpcoming = notifyOnUpcoming
        self.playNotificationSound = playNotificationSound
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}
