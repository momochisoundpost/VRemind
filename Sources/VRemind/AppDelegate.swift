import AppKit
import Combine
import SwiftUI
import VRemindKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?

    var channelStore: ChannelStore!
    var preferencesStore: PreferencesStore!
    var notificationService: NotificationService!
    var monitorService: StreamMonitorService!
    var updateService: UpdateService!
    var powerMonitor: PowerStateMonitor!
    var priorityManager: ProcessPriorityManager!
    var statusViewModel: MenuBarStatusViewModel!
    var updateTimer: Timer?
    var latestAvailableRelease: GitHubRelease?

    private var cancellables = Set<AnyCancellable>()

    override nonisolated init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let powerMonitor = PowerStateMonitor(observeSystemPowerSource: true)
        let priorityManager = ProcessPriorityManager(backend: .darwin)
        priorityManager.applyLaunchBaseline()

        self.powerMonitor = powerMonitor
        self.priorityManager = priorityManager

        let channelStore = ChannelStore()
        let preferencesStore = PreferencesStore()
        let notificationService = NotificationService()
        let monitorService = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: preferencesStore,
            notificationService: notificationService,
            powerMonitor: powerMonitor
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
        let (pop, viewModel) = MenuBarStatusView.makePopoverWithViewModel(
            channelStore: channelStore,
            monitorService: monitorService,
            powerMonitor: powerMonitor,
            onOpenPreferences: { [weak self] in
                self?.openPreferences()
            },
            onQuit: { [weak self] in
                self?.quitApp()
            }
        )
        pop.delegate = self
        self.popover = pop
        self.statusViewModel = viewModel
    }

    // MARK: - NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) {
        statusViewModel?.isPopoverVisible = true
        priorityManager?.beginUIActivity(.popover)
    }

    func popoverDidClose(_ notification: Notification) {
        statusViewModel?.isPopoverVisible = false
        priorityManager?.endUIActivity(.popover)
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
            },
            onRestore: { [weak self] in
                self?.handleRestore()
            },
            onVisibilityChange: { [weak self] isVisible in
                if isVisible {
                    self?.priorityManager?.beginUIActivity(.preferences)
                } else {
                    self?.priorityManager?.endUIActivity(.preferences)
                }
            },
            onUpdateVisibilityChange: { [weak self] isVisible in
                if isVisible {
                    self?.priorityManager?.beginUIActivity(.updateAvailable)
                } else {
                    self?.priorityManager?.endUIActivity(.updateAvailable)
                }
            }
        )
    }

    private func handleFactoryReset() {
        popover?.performClose(nil)
        Task { [weak self] in
            guard let self else { return }
            self.monitorService.clearStatuses()
            await self.monitorService.exportWidgetSnapshot()
            await self.monitorService.refreshAll()
            self.showOnboardingIfNeeded()
        }
    }

    private func handleRestore() {
        Task { [weak self] in
            guard let self else { return }
            self.monitorService.clearStatuses()
            await self.monitorService.exportWidgetSnapshot()
            await self.monitorService.refreshAll()
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
                },
                onVisibilityChange: { [weak self] isVisible in
                    if isVisible {
                        self?.priorityManager?.beginUIActivity(.onboarding)
                    } else {
                        self?.priorityManager?.endUIActivity(.onboarding)
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

    private func presentUpdateAvailableWindow(release: GitHubRelease) {
        UpdateAvailableWindowController.show(
            release: release,
            preferencesStore: preferencesStore,
            onVisibilityChange: { [weak self] isVisible in
                if isVisible {
                    self?.priorityManager?.beginUIActivity(.updateAvailable)
                } else {
                    self?.priorityManager?.endUIActivity(.updateAvailable)
                }
            }
        )
    }

    private func performLaunchUpdateCheck() {
        Task { [weak self] in
            guard let self else { return }
            let isLPM = self.powerMonitor.currentPolicy.deferBackgroundUpdateChecks
            let result = await self.updateService.checkForUpdates(manual: false, isLowPowerModeEnabled: isLPM)
            if case .updateAvailable(let release) = result {
                self.latestAvailableRelease = release
                self.presentUpdateAvailableWindow(release: release)
            }
        }
    }

    func startPeriodicUpdateChecksIfNeeded() {
        guard preferencesStore.settings.updateConsent == .allowed else { return }
        guard updateTimer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.performPeriodicUpdateCheck()
            }
        }
        timer.tolerance = 3_600
        updateTimer = timer
    }

    func stopPeriodicUpdateChecks() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    func performPeriodicUpdateCheck() async {
        guard preferencesStore.settings.updateConsent == .allowed else { return }
        let isLPM = powerMonitor.currentPolicy.deferBackgroundUpdateChecks
        let result = await updateService.checkForUpdates(manual: false, isLowPowerModeEnabled: isLPM)
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
                self.presentUpdateAvailableWindow(release: targetRelease)
            } else if case .updateAvailable(let rel) = self.updateService.lastResult {
                self.presentUpdateAvailableWindow(release: rel)
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
