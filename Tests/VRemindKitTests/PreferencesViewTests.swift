import Foundation
import SwiftUI
import Testing
import UserNotifications
@testable import VRemindKit

struct PreferencesViewTests {

    @Test @MainActor func testFactoryResetActionClearsAll() {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        store.addChannel(handle: "@extra", name: nil, avatarURL: nil)
        prefs.settings.notifyOnUpcoming = true
        prefs.settings.hasCompletedOnboarding = true

        let viewModel = PreferencesViewModel(preferencesStore: prefs, channelStore: store)
        viewModel.performFactoryReset()

        #expect(prefs.settings.hasCompletedOnboarding == false)
        #expect(prefs.settings.notifyOnUpcoming == false)
        #expect(store.channels.count == 1)
        #expect(store.channels[0].handle == "@bukancaitlyn")
    }

    @Test @MainActor func testSetLaunchAtLoginUpdatesPreferences() {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        let viewModel = PreferencesViewModel(preferencesStore: prefs, channelStore: store)

        viewModel.setLaunchAtLogin(true)
        #expect(prefs.settings.launchAtLogin == true)

        viewModel.setLaunchAtLogin(false)
        #expect(prefs.settings.launchAtLogin == false)
    }

    @Test @MainActor func testPerformFactoryResetInvokesCallbackAndDismissesConfirmation() {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        var didReset = false

        let viewModel = PreferencesViewModel(
            preferencesStore: prefs,
            channelStore: store,
            onFactoryReset: { didReset = true }
        )

        viewModel.isShowingResetConfirmation = true
        #expect(viewModel.isShowingResetConfirmation == true)

        viewModel.performFactoryReset()
        #expect(didReset == true)
        #expect(viewModel.isShowingResetConfirmation == false)
    }

    @Test func testPreferencesViewModelStaticCopyConstants() {
        #expect(
            PreferencesViewModel.attributionCopy ==
            "VRemind by Caitlyn Momochi, initially vibecoded for their Hackintosh video"
        )
        #expect(
            PreferencesViewModel.forkCopy ==
            "You don't like what I did? Go fork yourself, it's free and open source."
        )
    }

    @Test func testAppConstantsURLs() {
        #expect(AppConstants.youtubeChannelURL == URL(string: "https://www.youtube.com/@bukancaitlyn")!)
        #expect(AppConstants.twitterURL == URL(string: "https://twitter.com/Y2Karyl")!)
    }

    @Test @MainActor func testPreferencesViewModelNotificationInteractions() async {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        let fakeCenter = NoOpNotificationCenter(status: .denied)
        let service = NotificationService(center: fakeCenter)

        let viewModel = PreferencesViewModel(
            preferencesStore: prefs,
            channelStore: store,
            notificationService: service
        )

        #expect(viewModel.authorizationStatus == .notDetermined)

        await viewModel.refreshNotificationStatus()
        #expect(viewModel.authorizationStatus == .denied)

        await viewModel.requestNotifications()
        #expect(viewModel.authorizationStatus == .denied)
    }

    @Test @MainActor func testPreferencesViewModelNilNotificationServiceIsSafe() async {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        let viewModel = PreferencesViewModel(preferencesStore: prefs, channelStore: store)

        #expect(viewModel.authorizationStatus == .notDetermined)
        await viewModel.refreshNotificationStatus()
        #expect(viewModel.authorizationStatus == .notDetermined)
        await viewModel.requestNotifications()
        #expect(viewModel.authorizationStatus == .notDetermined)
    }

    @Test @MainActor func testPreferencesViewRendersWithoutCrash() {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        let viewModel = PreferencesViewModel(preferencesStore: prefs, channelStore: store)
        let view = PreferencesView(viewModel: viewModel)

        _ = view.body
    }
}
