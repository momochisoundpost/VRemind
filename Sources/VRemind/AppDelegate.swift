import AppKit
import Combine
import SwiftUI
import VRemindKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?

    var channelStore: ChannelStore!
    var preferencesStore: PreferencesStore!
    var notificationService: NotificationService!
    var monitorService: StreamMonitorService!
    var updateService: UpdateService!
    var updateTimer: Timer?
    var latestAvailableRelease: GitHubRelease?

    private var cancellables = Set<AnyCancellable>()

    override nonisolated init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let channelStore = ChannelStore()
        let preferencesStore = PreferencesStore()
        let notificationService = NotificationService()
        let monitorService = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: preferencesStore,
            notificationService: notificationService
        )
        let updateService = UpdateService(preferencesStore: preferencesStore)

        self.channelStore = channelStore
        self.preferencesStore = preferencesStore
        self.notificationService = notificationService
        self.monitorService = monitorService
        self.updateService = updateService

        setupNotificationHandling()
        setupStatusItem()
        setupPopover()
        setupObservations()
        updateStatusButton()

        monitorService.startPolling()
        Task { [weak self] in
            await self?.monitorService.checkDeveloperBirthdayNotificationIfNeeded()
        }

        showOnboardingIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPeriodicUpdateChecks()
        monitorService?.stopPolling()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let streamURL = LinkOpener.shared.parseStreamDeepLink(url) {
                LinkOpener.shared.open(streamURL)
            }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            MenuBarStatusView.configureStatusButton(button, isLive: false)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
    }

    private func setupPopover() {
        popover = MenuBarStatusView.makePopover(
            channelStore: channelStore,
            monitorService: monitorService,
            onOpenPreferences: { [weak self] in
                self?.openPreferences()
            },
            onQuit: { [weak self] in
                self?.quitApp()
            }
        )
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func openPreferences() {
        popover?.performClose(nil)
        PreferencesWindowController.show(
            preferencesStore: preferencesStore,
            channelStore: channelStore,
            notificationService: notificationService,
            updateService: updateService,
            onFactoryReset: { [weak self] in
                self?.handleFactoryReset()
            }
        )
    }

    private func handleFactoryReset() {
        popover?.performClose(nil)
        Task { [weak self] in
            guard let self else { return }
            await self.monitorService.refreshAll()
            self.showOnboardingIfNeeded()
        }
    }

    private func showOnboardingIfNeeded() {
        if !preferencesStore.settings.hasCompletedOnboarding {
            OnboardingWindowController.showIfNeeded(
                channelStore: channelStore,
                preferencesStore: preferencesStore,
                notificationService: notificationService,
                onComplete: { [weak self] in
                    Task { [weak self] in
                        await self?.monitorService.refreshAll()
                        self?.checkUpdateConsentAndLaunchCheck()
                    }
                }
            )
        } else {
            checkUpdateConsentAndLaunchCheck()
        }
    }

    func checkUpdateConsentAndLaunchCheck() {
        switch preferencesStore.settings.updateConsent {
        case .undecided:
            let alert = NSAlert()
            alert.messageText = "Enable Automatic Update Checks?"
            alert.informativeText = "VRemind can check GitHub Releases to notify you when new features and improvements are available. No personal data is transmitted."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Enable")
            alert.addButton(withTitle: "Not Now")

            let checkbox = NSButton(checkboxWithTitle: "Never ask again", target: nil, action: nil)
            checkbox.sizeToFit()
            alert.accessoryView = checkbox

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                preferencesStore.settings.updateConsent = .allowed
                performLaunchUpdateCheck()
                startPeriodicUpdateChecksIfNeeded()
            } else {
                if checkbox.state == .on {
                    preferencesStore.settings.updateConsent = .neverAsk
                }
            }
        case .allowed:
            performLaunchUpdateCheck()
            startPeriodicUpdateChecksIfNeeded()
        case .neverAsk:
            break
        }
    }

    private func performLaunchUpdateCheck() {
        Task { [weak self] in
            guard let self else { return }
            let result = await self.updateService.checkForUpdates(manual: false)
            if case .updateAvailable(let release) = result {
                self.latestAvailableRelease = release
                UpdateAvailableWindowController.show(release: release, preferencesStore: self.preferencesStore)
            }
        }
    }

    func startPeriodicUpdateChecksIfNeeded() {
        guard preferencesStore.settings.updateConsent == .allowed else { return }
        guard updateTimer == nil else { return }

        updateTimer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.performPeriodicUpdateCheck()
            }
        }
    }

    func stopPeriodicUpdateChecks() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    func performPeriodicUpdateCheck() async {
        guard preferencesStore.settings.updateConsent == .allowed else { return }
        let result = await updateService.checkForUpdates(manual: false)
        if case .updateAvailable(let release) = result {
            self.latestAvailableRelease = release
            await notificationService.notifyUpdate(release: release)
        }
    }

    private func setupNotificationHandling() {
        notificationService.onUpdateClicked = { [weak self] release in
            guard let self else { return }
            let targetRelease = release ?? self.latestAvailableRelease
            if let targetRelease {
                UpdateAvailableWindowController.show(release: targetRelease, preferencesStore: self.preferencesStore)
            } else if case .updateAvailable(let rel) = self.updateService.lastResult {
                UpdateAvailableWindowController.show(release: rel, preferencesStore: self.preferencesStore)
            }
        }
    }

    private func quitApp() {
        NSApp.terminate(nil)
    }

    private func setupObservations() {
        monitorService.$statuses
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
            }
            .store(in: &cancellables)

        channelStore.$channels
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
            }
            .store(in: &cancellables)

        preferencesStore.$settings
            .map { $0.updateConsent }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] consent in
                if consent == .allowed {
                    self?.startPeriodicUpdateChecksIfNeeded()
                } else {
                    self?.stopPeriodicUpdateChecks()
                }
            }
            .store(in: &cancellables)

        preferencesStore.$settings
            .map(\.reduceMotion)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
            }
            .store(in: &cancellables)
    }

    private func updateStatusButton() {
        guard let button = statusItem?.button else { return }
        MenuBarStatusView.configureStatusButton(button, isLive: monitorService.isAnyLive)
    }
}
