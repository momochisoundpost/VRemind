import AppKit
import CaitlynKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var configService = ConfigSyncService(cacheDirectory: ConfigSyncService.defaultCacheDirectory())
    private lazy var liveService = LiveStatusService()
    private lazy var watchlistService = WatchlistService(configService: configService)

    private var statusItem: NSStatusItem?
    private lazy var popover = NSPopover()
    private var mainWindow: NSWindow?
    private var pollTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    override nonisolated init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        observeStatus()
        observeScreenSleepWake()

        Task {
            await configService.sync()
        }
        Task {
            await watchlistService.refreshAll()
            await liveService.refresh()
        }
        startPollTimer()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        self.statusItem = item
        updateStatusButton(isLive: watchlistService.isAnyLive)
    }

    private func setupPopover() {
        popover = MenuBarStatusView.makePopover(
            configService: configService,
            watchlistService: watchlistService,
            onOpenHub: { [weak self] in
                self?.openMainHub()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )
    }

    private func observeStatus() {
        watchlistService.$statuses
            .combineLatest(watchlistService.$customChannels)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.updateStatusButton(isLive: self.watchlistService.isAnyLive)
                if let view = self.popover.contentViewController?.view {
                    view.invalidateIntrinsicContentSize()
                    view.layoutSubtreeIfNeeded()
                    self.popover.contentSize = view.fittingSize
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusButton(isLive: Bool) {
        guard let button = statusItem?.button else { return }
        let symbolName = isLive ? "dot.radiowaves.left.and.right" : "sparkles"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Caitlyn Momochi")
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = isLive ? .systemRed : nil
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem?.button {
            if let view = popover.contentViewController?.view {
                popover.contentSize = view.fittingSize
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func openMainHub() {
        if popover.isShown {
            popover.performClose(nil)
        }
        if mainWindow == nil {
            let hubView = MainHubView(configService: configService, liveService: liveService)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Caitlyn Momochi"
            window.contentView = NSHostingView(rootView: hubView)
            window.isReleasedWhenClosed = false
            window.center()
            self.mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startPollTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.livePollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.watchlistService.refreshAll()
                await self?.liveService.refresh()
            }
        }
    }

    private func observeScreenSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollTimer?.invalidate()
                self?.pollTimer = nil
            }
        }
        center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.watchlistService.refreshAll()
                await self?.liveService.refresh()
                self?.startPollTimer()
            }
        }
    }
}
