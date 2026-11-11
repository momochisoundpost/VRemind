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

    private var cancellables = Set<AnyCancellable>()
    private var flashTimer: Timer?
    private var flashPhase: Bool = false

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

        self.channelStore = channelStore
        self.preferencesStore = preferencesStore
        self.notificationService = notificationService
        self.monitorService = monitorService

        setupStatusItem()
        setupPopover()
        setupObservations()
        updateStatusButton()

        monitorService.startPolling()

        showOnboardingIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        flashTimer?.invalidate()
        flashTimer = nil
        monitorService?.stopPolling()
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
        OnboardingWindowController.showIfNeeded(
            channelStore: channelStore,
            preferencesStore: preferencesStore,
            notificationService: notificationService,
            onComplete: { [weak self] in
                Task { [weak self] in
                    await self?.monitorService.refreshAll()
                }
            }
        )
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
    }

    private func updateStatusButton() {
        guard let button = statusItem?.button else { return }
        let isAnyLive = monitorService.isAnyLive

        if isAnyLive {
            if flashTimer == nil {
                flashPhase = true
                flashTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.flashPhase.toggle()
                        if let btn = self.statusItem?.button {
                            MenuBarStatusView.configureStatusButton(btn, isLive: true, flashPhase: self.flashPhase)
                        }
                    }
                }
            }
            MenuBarStatusView.configureStatusButton(button, isLive: true, flashPhase: flashPhase)
        } else {
            flashTimer?.invalidate()
            flashTimer = nil
            flashPhase = false
            MenuBarStatusView.configureStatusButton(button, isLive: false)
        }
    }
}
