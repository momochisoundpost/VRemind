import Foundation

@MainActor
public final class PreferencesStore: ObservableObject {
    public nonisolated static let userDefaultsKey = "vremind.preferences"

    @Published public var settings: AppSettings {
        didSet {
            save()
        }
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
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
