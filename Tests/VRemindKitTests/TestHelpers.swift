import Foundation

func makeTestDefaults() -> UserDefaults {
    let suiteName = "test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
