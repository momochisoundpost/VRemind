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
}
