import Foundation
import VRemindCore

private struct SendableUserDefaults: @unchecked Sendable {
    let defaults: UserDefaults
}

@MainActor
public final class PreferencesStore: ObservableObject {
    public nonisolated static let userDefaultsKey = "vremind.preferences"

    @Published public var settings: AppSettings {
        didSet {
            save()
        }
    }

    private let storage: SendableUserDefaults
    private var userDefaults: UserDefaults { storage.defaults }

    public init(userDefaults: UserDefaults = .standard) {
        self.storage = SendableUserDefaults(defaults: userDefaults)
        if let data = userDefaults.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            // AppSettings decodes backward-compatibly, defaulting updateConsent to .undecided
            // and nullable fields to nil if omitted in older stored settings.
            self.settings = decoded
        } else {
            let defaults = AppSettings()
            self.settings = defaults
            if let data = try? JSONEncoder().encode(defaults) {
                userDefaults.set(data, forKey: Self.userDefaultsKey)
            }
        }
    }

    public func resetToDefaults() {
        settings = AppSettings()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: Self.userDefaultsKey)
        }
    }
}

extension PreferencesStore: SettingsStorage, @unchecked Sendable {
    public nonisolated func loadSettings() throws -> AppSettings {
        guard let data = storage.defaults.data(forKey: Self.userDefaultsKey) else {
            return AppSettings()
        }
        return try JSONDecoder().decode(AppSettings.self, from: data)
    }

    public nonisolated func saveSettings(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        storage.defaults.set(data, forKey: Self.userDefaultsKey)
        Task { @MainActor in
            self.settings = settings
        }
    }
}
