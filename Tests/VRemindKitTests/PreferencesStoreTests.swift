import Foundation
import Testing
@testable import VRemindKit

struct PreferencesStoreTests {
    @Test @MainActor func initialDefaults() async {
        let store = PreferencesStore(userDefaults: makeTestDefaults())
        #expect(store.settings.launchAtLogin == false)
        #expect(store.settings.notifyOnLive == true)
        #expect(store.settings.notifyOnUpcoming == false)
        #expect(store.settings.playNotificationSound == true)
        #expect(store.settings.hasCompletedOnboarding == false)
    }

    @Test @MainActor func mutationPersistsAutomatically() async {
        let defaults = makeTestDefaults()
        let store1 = PreferencesStore(userDefaults: defaults)

        store1.settings.launchAtLogin = true
        store1.settings.notifyOnLive = false
        store1.settings.notifyOnUpcoming = true
        store1.settings.playNotificationSound = false
        store1.settings.hasCompletedOnboarding = true

        let store2 = PreferencesStore(userDefaults: defaults)
        #expect(store2.settings.launchAtLogin == true)
        #expect(store2.settings.notifyOnLive == false)
        #expect(store2.settings.notifyOnUpcoming == true)
        #expect(store2.settings.playNotificationSound == false)
        #expect(store2.settings.hasCompletedOnboarding == true)
    }

    @Test @MainActor func resetToDefaultsRestoresDefaults() async {
        let defaults = makeTestDefaults()
        let store1 = PreferencesStore(userDefaults: defaults)

        store1.settings.launchAtLogin = true
        store1.settings.notifyOnUpcoming = true
        store1.settings.hasCompletedOnboarding = true

        store1.resetToDefaults()
        #expect(store1.settings == AppSettings())

        let store2 = PreferencesStore(userDefaults: defaults)
        #expect(store2.settings == AppSettings())
    }

    @Test("Update consent defaults to undecided and round-trips via PreferencesStore")
    @MainActor
    func testUpdateConsentSettingsPersistence() async {
        let defaults = UserDefaults(suiteName: "test.preferences.updates.\(UUID().uuidString)")!
        let store = PreferencesStore(userDefaults: defaults)

        #expect(store.settings.updateConsent == .undecided)
        #expect(store.settings.lastUpdateCheckDate == nil)
        #expect(store.settings.ignoredUpdateTag == nil)

        store.settings.updateConsent = .allowed
        store.settings.ignoredUpdateTag = "v1.0.0"
        let now = Date()
        store.settings.lastUpdateCheckDate = now

        let reloadedStore = PreferencesStore(userDefaults: defaults)
        #expect(reloadedStore.settings.updateConsent == .allowed)
        #expect(reloadedStore.settings.ignoredUpdateTag == "v1.0.0")
        #expect(reloadedStore.settings.lastUpdateCheckDate != nil)

        // Verify .neverAsk state also persists cleanly
        reloadedStore.settings.updateConsent = .neverAsk
        let thirdStore = PreferencesStore(userDefaults: defaults)
        #expect(thirdStore.settings.updateConsent == .neverAsk)
    }

    @Test("Loads legacy preferences without update consent gracefully")
    @MainActor
    func testLegacyPreferencesDecodeGracefully() async {
        let suiteName = "test.preferences.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        // Legacy JSON format with only original 5 fields
        let legacyJSON = """
        {
            "launchAtLogin": true,
            "notifyOnLive": false,
            "notifyOnUpcoming": true,
            "playNotificationSound": false,
            "hasCompletedOnboarding": true
        }
        """.data(using: .utf8)!
        defaults.set(legacyJSON, forKey: PreferencesStore.userDefaultsKey)

        let store = PreferencesStore(userDefaults: defaults)
        #expect(store.settings.launchAtLogin == true)
        #expect(store.settings.notifyOnLive == false)
        #expect(store.settings.notifyOnUpcoming == true)
        #expect(store.settings.playNotificationSound == false)
        #expect(store.settings.hasCompletedOnboarding == true)
        #expect(store.settings.updateConsent == .undecided)
        #expect(store.settings.lastUpdateCheckDate == nil)
        #expect(store.settings.ignoredUpdateTag == nil)
        #expect(store.settings.reduceMotion == false)
        #expect(store.settings.lastNotifiedDevBirthdayYear == nil)
    }

    @Test("Reduce motion and developer birthday year persist and reset")
    @MainActor
    func testReduceMotionAndDevBirthdayYearPersistence() async {
        let defaults = makeTestDefaults()
        let store1 = PreferencesStore(userDefaults: defaults)

        #expect(store1.settings.reduceMotion == false)
        #expect(store1.settings.lastNotifiedDevBirthdayYear == nil)

        store1.settings.reduceMotion = true
        store1.settings.lastNotifiedDevBirthdayYear = 2026

        let store2 = PreferencesStore(userDefaults: defaults)
        #expect(store2.settings.reduceMotion == true)
        #expect(store2.settings.lastNotifiedDevBirthdayYear == 2026)

        store2.resetToDefaults()
        #expect(store2.settings.reduceMotion == false)
        #expect(store2.settings.lastNotifiedDevBirthdayYear == nil)

        let store3 = PreferencesStore(userDefaults: defaults)
        #expect(store3.settings.reduceMotion == false)
        #expect(store3.settings.lastNotifiedDevBirthdayYear == nil)
    }
}
