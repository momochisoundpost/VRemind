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

    @Test("PreferencesViewModel exposes update checking and toggles consent")
    @MainActor
    func testPreferencesViewModelUpdates() async {
        let defaults = UserDefaults(suiteName: "test.pref.updates.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let channels = ChannelStore(userDefaults: defaults)
        let updateService = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: {
                GitHubRelease(
                    tagName: "v1.0.0",
                    name: "v1.0.0",
                    body: nil,
                    htmlURL: URL(string: "https://github.com")!,
                    publishedAt: nil,
                    assets: []
                )
            }
        )

        let vm = PreferencesViewModel(
            preferencesStore: prefs,
            channelStore: channels,
            notificationService: nil,
            updateService: updateService
        )

        #expect(vm.isAutoUpdateEnabled == false)
        vm.setAutoUpdateEnabled(true)
        #expect(prefs.settings.updateConsent == .allowed)
        #expect(vm.isAutoUpdateEnabled == true)

        let result = await vm.checkForUpdatesManually()
        #expect(result == .localVersionNewer(remoteVersion: "v1.0.0"))
        #expect(vm.isShowingEasterEggAlert == true)
    }

    @Test("PreferencesViewModel disables auto updates to neverAsk")
    @MainActor
    func testPreferencesViewModelDisableAutoUpdates() {
        let defaults = UserDefaults(suiteName: "test.pref.updates.disable.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let channels = ChannelStore(userDefaults: defaults)
        let vm = PreferencesViewModel(
            preferencesStore: prefs,
            channelStore: channels,
            notificationService: nil
        )

        vm.isAutoUpdateEnabled = true
        #expect(prefs.settings.updateConsent == .allowed)
        #expect(vm.isAutoUpdateEnabled == true)

        vm.isAutoUpdateEnabled = false
        #expect(prefs.settings.updateConsent == .neverAsk)
        #expect(vm.isAutoUpdateEnabled == false)
    }

    @Test("PreferencesViewModel handles available update and triggers callback")
    @MainActor
    func testPreferencesViewModelAvailableUpdate() async {
        let defaults = UserDefaults(suiteName: "test.pref.updates.avail.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let channels = ChannelStore(userDefaults: defaults)
        let targetRelease = GitHubRelease(
            tagName: "v1.0.2",
            name: "v1.0.2",
            body: "Notes",
            htmlURL: URL(string: "https://github.com")!,
            publishedAt: nil,
            assets: []
        )
        let updateService = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: { targetRelease }
        )

        var notifiedRelease: GitHubRelease?
        let vm = PreferencesViewModel(
            preferencesStore: prefs,
            channelStore: channels,
            notificationService: nil,
            updateService: updateService,
            onUpdateAvailable: { release in
                notifiedRelease = release
            }
        )

        let result = await vm.checkForUpdatesManually()
        #expect(result == .updateAvailable(targetRelease))
        #expect(notifiedRelease == targetRelease)
        #expect(vm.updateStatusText?.contains("v1.0.2") == true)
        #expect(vm.isShowingEasterEggAlert == false)
    }

    @Test("PreferencesViewModel handles nil update service safely")
    @MainActor
    func testPreferencesViewModelNilUpdateService() async {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        let vm = PreferencesViewModel(
            preferencesStore: prefs,
            channelStore: store,
            notificationService: nil,
            updateService: nil
        )

        let result = await vm.checkForUpdatesManually()
        #expect(result == nil)
        #expect(vm.updateStatusText == "Update service unavailable")
    }

    @Test("PreferencesViewModel handles upToDate and failed results")
    @MainActor
    func testPreferencesViewModelOtherResults() async {
        let defaults = UserDefaults(suiteName: "test.pref.updates.other.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let store = ChannelStore(userDefaults: defaults)

        let upToDateService = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: {
                GitHubRelease(
                    tagName: "v1.0.1",
                    name: "v1.0.1",
                    body: nil,
                    htmlURL: URL(string: "https://github.com")!,
                    publishedAt: nil,
                    assets: []
                )
            }
        )

        let vm = PreferencesViewModel(
            preferencesStore: prefs,
            channelStore: store,
            notificationService: nil,
            updateService: upToDateService
        )

        let result = await vm.checkForUpdatesManually()
        #expect(result == .upToDate(latestVersion: "v1.0.1"))
        #expect(vm.updateStatusText?.contains("up to date") == true)
        #expect(vm.isShowingEasterEggAlert == false)

        let failingService = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: { throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network timeout"]) }
        )
        let vmFail = PreferencesViewModel(
            preferencesStore: prefs,
            channelStore: store,
            notificationService: nil,
            updateService: failingService
        )
        let failResult = await vmFail.checkForUpdatesManually()
        #expect(failResult == .failed("Network timeout"))
        #expect(vmFail.updateStatusText?.contains("Network timeout") == true)
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
        #expect(AppConstants.githubURL == URL(string: "https://github.com/momochisoundpost")!)
        #expect(AppConstants.instagramURL == URL(string: "https://www.instagram.com/bukancaitlyn")!)
    }

    @Test func testBrandIconsLoadCorrectly() {
        let gh = BrandIcon.githubImage
        #expect(gh.size.width > 0)
        #expect(gh.size.height > 0)
        #expect(gh.isTemplate == true)

        let ig = BrandIcon.instagramImage
        #expect(ig.size.width > 0)
        #expect(ig.size.height > 0)
        #expect(ig.isTemplate == true)

        let appIcon = BrandIcon.appIconImage
        #expect(appIcon != nil)
        #expect(appIcon?.size.width ?? 0 > 0)
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

    @Test @MainActor func testPreferencesViewModelDefaultNotificationServiceIsCreated() {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        let viewModel = PreferencesViewModel(preferencesStore: prefs, channelStore: store)

        #expect(viewModel.notificationService != nil)
    }

    @Test @MainActor func testPreferencesViewModelNilNotificationServiceIsSafe() async {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        let viewModel = PreferencesViewModel(
            preferencesStore: prefs,
            channelStore: store,
            notificationService: nil
        )

        #expect(viewModel.notificationService == nil)
        #expect(viewModel.authorizationStatus == .notDetermined)
        await viewModel.refreshNotificationStatus()
        #expect(viewModel.authorizationStatus == .notDetermined)
        await viewModel.requestNotifications()
        #expect(viewModel.authorizationStatus == .notDetermined)

        let view = PreferencesView(viewModel: viewModel)
        _ = view.body
    }

    @Test @MainActor func testPreferencesViewRendersWithoutCrash() {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let store = ChannelStore(userDefaults: makeTestDefaults())
        let viewModel = PreferencesViewModel(preferencesStore: prefs, channelStore: store)
        let view = PreferencesView(viewModel: viewModel)

        _ = view.body
    }

    @Test @MainActor func testReduceMotionBindingAndReset() {
        let defaults = makeTestDefaults()
        let prefs = PreferencesStore(userDefaults: defaults)
        let store = ChannelStore(userDefaults: defaults)
        let viewModel = PreferencesViewModel(preferencesStore: prefs, channelStore: store)

        #expect(prefs.settings.reduceMotion == false)
        prefs.settings.reduceMotion = true
        #expect(prefs.settings.reduceMotion == true)

        let reloadedPrefs = PreferencesStore(userDefaults: defaults)
        #expect(reloadedPrefs.settings.reduceMotion == true)

        viewModel.performFactoryReset()
        #expect(prefs.settings.reduceMotion == false)

        let view = PreferencesView(viewModel: viewModel)
        let controller = NSHostingController(rootView: view)
        #expect(controller.view.bounds.width >= 0)
    }

    @Test @MainActor func testExportBackupWritesValidJSONFile() throws {
        let defaults = makeTestDefaults()
        let prefs = PreferencesStore(userDefaults: defaults)
        let store = ChannelStore(userDefaults: defaults)
        prefs.settings.notifyOnUpcoming = true
        store.addChannel(handle: "@test_vtuber")

        let viewModel = PreferencesViewModel(preferencesStore: prefs, channelStore: store)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vremind-export-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        viewModel.exportBackup(chooseSaveURL: { tempURL })

        let data = try Data(contentsOf: tempURL)
        let decoded = try BackupPayload.decodeAndValidate(from: data)
        #expect(decoded.settings.notifyOnUpcoming == true)
        #expect(decoded.channels.contains { $0.handle == "@test_vtuber" })
        #expect(viewModel.backupStatusText != nil)
        #expect(viewModel.backupErrorMessage == nil)
    }

    @Test @MainActor func testRestoreBackupOverwritesStoresSanitizesAndTriggersCallback() async throws {
        let defaults = makeTestDefaults()
        let prefs = PreferencesStore(userDefaults: defaults)
        let store = ChannelStore(userDefaults: defaults)
        try store.saveChannels([
            WatchedChannel(id: "youtube:@bukancaitlyn", platform: .youtube, name: "Caitlyn", handle: "@bukancaitlyn"),
            WatchedChannel(id: "youtube:@other", platform: .youtube, name: "Other", handle: "@other")
        ])
        await Task.yield()

        var backupSettings = AppSettings()
        backupSettings.hasCompletedOnboarding = false
        backupSettings.notifyOnUpcoming = true
        backupSettings.reduceMotion = true
        var twitchChannel = WatchedChannel(id: "twitch:ironmouse", platform: .twitch, name: "ironmouse", handle: "ironmouse")
        twitchChannel.lastNotifiedVideoId = "old123"
        let payload = BackupPayload(settings: backupSettings, channels: [twitchChannel])
        let backupData = try payload.encodedJSONData()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vremind-restore-test-\(UUID().uuidString).json")
        try backupData.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var callbackFired = false
        let viewModel = PreferencesViewModel(
            preferencesStore: prefs,
            channelStore: store,
            onRestore: { callbackFired = true }
        )

        viewModel.restoreBackup(chooseOpenURL: { tempURL })
        #expect(viewModel.isShowingRestoreConfirmation == true)
        #expect(viewModel.pendingRestorePayload != nil)
        #expect(store.channels.count == 2)
        #expect(callbackFired == false)

        viewModel.confirmRestore()
        await Task.yield()
        #expect(viewModel.isShowingRestoreConfirmation == false)
        #expect(viewModel.pendingRestorePayload == nil)
        #expect(callbackFired == true)
        #expect(store.channels.count == 1)
        #expect(store.channels.first?.id == "twitch:ironmouse")
        #expect(store.channels.first?.lastNotifiedVideoId == nil)
        #expect(prefs.settings.hasCompletedOnboarding == true)
        #expect(prefs.settings.notifyOnUpcoming == true)
        #expect(prefs.settings.reduceMotion == true)
        #expect(viewModel.backupStatusText != nil)
        #expect(viewModel.backupErrorMessage == nil)
    }

    @Test @MainActor func testRestoreInvalidFileSurfacesErrorWithoutMutatingStores() async throws {
        let defaults = makeTestDefaults()
        let prefs = PreferencesStore(userDefaults: defaults)
        let store = ChannelStore(userDefaults: defaults)
        try store.saveChannels([
            WatchedChannel(id: "youtube:@existing", platform: .youtube, name: "Existing", handle: "@existing")
        ])
        await Task.yield()
        prefs.settings.notifyOnUpcoming = false

        let viewModel = PreferencesViewModel(preferencesStore: prefs, channelStore: store)
        viewModel.prepareRestore(from: Data("not json".utf8))

        #expect(viewModel.backupErrorMessage != nil)
        #expect(viewModel.isShowingRestoreConfirmation == false)
        #expect(viewModel.pendingRestorePayload == nil)
        #expect(store.channels.count == 1)
        #expect(store.channels.first?.handle == "@existing")
        #expect(prefs.settings.notifyOnUpcoming == false)
    }

    @Test @MainActor func testCancelRestoreClearsPendingPayloadWithoutMutatingStores() async throws {
        let defaults = makeTestDefaults()
        let prefs = PreferencesStore(userDefaults: defaults)
        let store = ChannelStore(userDefaults: defaults)
        try store.saveChannels([
            WatchedChannel(id: "youtube:@existing", platform: .youtube, name: "Existing", handle: "@existing")
        ])
        await Task.yield()

        let payload = BackupPayload(
            settings: AppSettings(),
            channels: [WatchedChannel(id: "twitch:ironmouse", platform: .twitch, name: "ironmouse", handle: "ironmouse")]
        )
        let validData = try payload.encodedJSONData()

        let viewModel = PreferencesViewModel(preferencesStore: prefs, channelStore: store)
        viewModel.prepareRestore(from: validData)
        #expect(viewModel.isShowingRestoreConfirmation == true)
        #expect(viewModel.pendingRestorePayload != nil)

        viewModel.cancelRestore()
        #expect(viewModel.isShowingRestoreConfirmation == false)
        #expect(viewModel.pendingRestorePayload == nil)
        #expect(store.channels.count == 1)
        #expect(store.channels.first?.handle == "@existing")
    }
}
