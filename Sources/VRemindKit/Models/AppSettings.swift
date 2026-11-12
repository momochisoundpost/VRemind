import Foundation

public enum UpdateConsentState: String, Codable, Sendable, CaseIterable {
    case undecided
    case allowed
    case neverAsk
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var launchAtLogin: Bool
    public var notifyOnLive: Bool
    public var notifyOnUpcoming: Bool
    public var playNotificationSound: Bool
    public var hasCompletedOnboarding: Bool
    public var updateConsent: UpdateConsentState
    public var lastUpdateCheckDate: Date?
    public var ignoredUpdateTag: String?

    public init(
        launchAtLogin: Bool = false,
        notifyOnLive: Bool = true,
        notifyOnUpcoming: Bool = false,
        playNotificationSound: Bool = true,
        hasCompletedOnboarding: Bool = false,
        updateConsent: UpdateConsentState = .undecided,
        lastUpdateCheckDate: Date? = nil,
        ignoredUpdateTag: String? = nil
    ) {
        self.launchAtLogin = launchAtLogin
        self.notifyOnLive = notifyOnLive
        self.notifyOnUpcoming = notifyOnUpcoming
        self.playNotificationSound = playNotificationSound
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.updateConsent = updateConsent
        self.lastUpdateCheckDate = lastUpdateCheckDate
        self.ignoredUpdateTag = ignoredUpdateTag
    }

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case notifyOnLive
        case notifyOnUpcoming
        case playNotificationSound
        case hasCompletedOnboarding
        case updateConsent
        case lastUpdateCheckDate
        case ignoredUpdateTag
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        notifyOnLive = try container.decodeIfPresent(Bool.self, forKey: .notifyOnLive) ?? true
        notifyOnUpcoming = try container.decodeIfPresent(Bool.self, forKey: .notifyOnUpcoming) ?? false
        playNotificationSound = try container.decodeIfPresent(Bool.self, forKey: .playNotificationSound) ?? true
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        updateConsent = (try? container.decodeIfPresent(UpdateConsentState.self, forKey: .updateConsent)) ?? .undecided
        lastUpdateCheckDate = try? container.decodeIfPresent(Date.self, forKey: .lastUpdateCheckDate)
        ignoredUpdateTag = try? container.decodeIfPresent(String.self, forKey: .ignoredUpdateTag)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(notifyOnLive, forKey: .notifyOnLive)
        try container.encode(notifyOnUpcoming, forKey: .notifyOnUpcoming)
        try container.encode(playNotificationSound, forKey: .playNotificationSound)
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try container.encode(updateConsent, forKey: .updateConsent)
        try container.encodeIfPresent(lastUpdateCheckDate, forKey: .lastUpdateCheckDate)
        try container.encodeIfPresent(ignoredUpdateTag, forKey: .ignoredUpdateTag)
    }
}
