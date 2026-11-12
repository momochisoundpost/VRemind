import Foundation
import SwiftUI
import Testing
import UserNotifications
@testable import VRemindKit

struct OnboardingViewTests {
    @Test @MainActor func testOnboardingCompletionMarksSettings() async {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        let viewModel = OnboardingViewModel(channelStore: store, preferencesStore: prefs)

        #expect(!prefs.settings.hasCompletedOnboarding)
        viewModel.customHandle = "@pekorach"
        let success = viewModel.completeOnboarding()

        #expect(success == true)
        #expect(prefs.settings.hasCompletedOnboarding == true)
        #expect(store.channels.contains(where: { $0.handle == "@pekorach" }))
    }

    @Test @MainActor func testOnboardingKeepDefaultChannel() async {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        var didComplete = false
        let viewModel = OnboardingViewModel(
            channelStore: store,
            preferencesStore: prefs,
            onComplete: { didComplete = true }
        )

        #expect(viewModel.customHandle == "@bukancaitlyn")
        let success = viewModel.completeOnboarding()

        #expect(success == true)
        #expect(didComplete == true)
        #expect(prefs.settings.hasCompletedOnboarding == true)
        #expect(store.channels.count == 1)
        #expect(store.channels.first?.id == "@bukancaitlyn")
        #expect(viewModel.validationError == nil)
    }

    @Test @MainActor func testOnboardingBlankHandleUsesDefaultChannel() async {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        let viewModel = OnboardingViewModel(channelStore: store, preferencesStore: prefs)

        viewModel.customHandle = "   "
        let success = viewModel.completeOnboarding()

        #expect(success == true)
        #expect(prefs.settings.hasCompletedOnboarding == true)
        #expect(store.channels.contains(where: { $0.id == "@bukancaitlyn" }))
        #expect(viewModel.validationError == nil)
    }

    @Test @MainActor func testOnboardingReplacesDefaultChannelWhenOnlyDefaultExists() async {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        #expect(store.channels.count == 1)
        #expect(store.channels.first?.id == "@bukancaitlyn")

        let viewModel = OnboardingViewModel(channelStore: store, preferencesStore: prefs)
        viewModel.customHandle = "https://www.youtube.com/@pekorach"
        let success = viewModel.completeOnboarding()

        #expect(success == true)
        #expect(store.channels.count == 1)
        #expect(store.channels.first?.handle == "@pekorach")
        #expect(!store.channels.contains(where: { $0.id == "@bukancaitlyn" }))
    }

    @Test @MainActor func testOnboardingAppendsChannelWhenMultipleChannelsExist() async {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        store.addChannel(handle: "@suiseihoshimati", name: "Suisei", avatarURL: nil)
        #expect(store.channels.count == 2)

        let viewModel = OnboardingViewModel(channelStore: store, preferencesStore: prefs)
        viewModel.customHandle = "@pekorach"
        let success = viewModel.completeOnboarding()

        #expect(success == true)
        #expect(store.channels.count == 3)
        #expect(store.channels.contains(where: { $0.id == "@bukancaitlyn" }))
        #expect(store.channels.contains(where: { $0.handle == "@suiseihoshimati" }))
        #expect(store.channels.contains(where: { $0.handle == "@pekorach" }))
    }

    @Test @MainActor func testOnboardingInvalidHandleFailsValidation() async {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        var didComplete = false
        let viewModel = OnboardingViewModel(
            channelStore: store,
            preferencesStore: prefs,
            onComplete: { didComplete = true }
        )

        viewModel.customHandle = "invalid handle with whitespace"
        let success = viewModel.completeOnboarding()

        #expect(success == false)
        #expect(didComplete == false)
        #expect(prefs.settings.hasCompletedOnboarding == false)
        #expect(viewModel.validationError != nil)
        #expect(!store.channels.contains(where: { $0.handle == "invalid handle with whitespace" }))
    }

    @Test @MainActor func testOnboardingRequestNotificationsUpdatesStatus() async {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        let mockCenter = MockNotificationCenter()
        mockCenter.requestAuthorizationResult = true
        let notifier = NotificationService(center: mockCenter)
        let viewModel = OnboardingViewModel(
            channelStore: store,
            preferencesStore: prefs,
            notificationService: notifier
        )

        #expect(viewModel.authorizationStatus == .notDetermined)
        await viewModel.requestNotifications()
        #expect(viewModel.authorizationStatus == .authorized)
    }

    @Test @MainActor func testOnboardingViewRendersWithoutCrash() async {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        let viewModel = OnboardingViewModel(channelStore: store, preferencesStore: prefs)
        let view = OnboardingView(viewModel: viewModel)

        // Ensure body property can be accessed without crashing
        _ = view.body
    }

    @Test("Onboarding completion sets updateConsent to allowed when enabled")
    @MainActor
    func testOnboardingUpdateConsentEnabled() {
        let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.onboarding.consent.on.\(UUID().uuidString)")!)
        let channels = ChannelStore(userDefaults: UserDefaults(suiteName: "test.onboarding.channels.on.\(UUID().uuidString)")!)
        let vm = OnboardingViewModel(channelStore: channels, preferencesStore: prefs)

        #expect(vm.enableUpdateChecks == true)
        #expect(vm.neverAskUpdatesAgain == false)
        _ = vm.completeOnboarding()

        #expect(prefs.settings.updateConsent == .allowed)
    }

    @Test("Onboarding completion sets updateConsent to neverAsk when disabled and neverAsk checked")
    @MainActor
    func testOnboardingUpdateConsentNeverAsk() {
        let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.onboarding.consent.never.\(UUID().uuidString)")!)
        let channels = ChannelStore(userDefaults: UserDefaults(suiteName: "test.onboarding.channels.never.\(UUID().uuidString)")!)
        let vm = OnboardingViewModel(channelStore: channels, preferencesStore: prefs)

        vm.enableUpdateChecks = false
        vm.neverAskUpdatesAgain = true
        _ = vm.completeOnboarding()

        #expect(prefs.settings.updateConsent == .neverAsk)
    }

    @Test("Onboarding completion leaves updateConsent undecided when disabled but neverAsk unchecked")
    @MainActor
    func testOnboardingUpdateConsentUndecidedWhenUnchecked() {
        let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.onboarding.consent.undecided.\(UUID().uuidString)")!)
        let channels = ChannelStore(userDefaults: UserDefaults(suiteName: "test.onboarding.channels.undecided.\(UUID().uuidString)")!)
        let vm = OnboardingViewModel(channelStore: channels, preferencesStore: prefs)

        vm.enableUpdateChecks = false
        vm.neverAskUpdatesAgain = false
        _ = vm.completeOnboarding()

        #expect(prefs.settings.updateConsent == .undecided)
    }
}
