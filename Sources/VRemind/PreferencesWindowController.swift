import AppKit
import SwiftUI
import VRemindKit

@MainActor
public final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private static var currentController: PreferencesWindowController?

    private var onVisibilityChange: ((Bool) -> Void)?
    private var onUpdateVisibilityChange: ((Bool) -> Void)?

    public static func show(
        preferencesStore: PreferencesStore,
        channelStore: ChannelStore,
        notificationService: NotificationService? = nil,
        updateService: UpdateService? = nil,
        onFactoryReset: (() -> Void)? = nil,
        onRestore: (() -> Void)? = nil,
        onVisibilityChange: ((Bool) -> Void)? = nil,
        onUpdateVisibilityChange: ((Bool) -> Void)? = nil
    ) {
        if let existing = currentController {
            if let onVisibilityChange {
                existing.onVisibilityChange = onVisibilityChange
            }
            if let onUpdateVisibilityChange {
                existing.onUpdateVisibilityChange = onUpdateVisibilityChange
            }
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            existing.onVisibilityChange?(true)
            return
        }

        let resolvedService = notificationService ?? NotificationService()
        let resolvedUpdateService = updateService ?? UpdateService(preferencesStore: preferencesStore)
        let controller = PreferencesWindowController(
            preferencesStore: preferencesStore,
            channelStore: channelStore,
            notificationService: resolvedService,
            updateService: resolvedUpdateService,
            onFactoryReset: onFactoryReset,
            onRestore: onRestore,
            onVisibilityChange: onVisibilityChange,
            onUpdateVisibilityChange: onUpdateVisibilityChange
        )
        currentController = controller
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.onVisibilityChange?(true)
    }

    public static var isShowing: Bool {
        currentController != nil
    }

    public static func close() {
        currentController?.close()
        currentController = nil
    }

    public init(
        preferencesStore: PreferencesStore,
        channelStore: ChannelStore,
        notificationService: NotificationService? = nil,
        updateService: UpdateService? = nil,
        onFactoryReset: (() -> Void)? = nil,
        onRestore: (() -> Void)? = nil,
        onVisibilityChange: ((Bool) -> Void)? = nil,
        onUpdateVisibilityChange: ((Bool) -> Void)? = nil
    ) {
        self.onVisibilityChange = onVisibilityChange
        self.onUpdateVisibilityChange = onUpdateVisibilityChange

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        let resolvedService = notificationService ?? NotificationService()
        let resolvedUpdateService = updateService ?? UpdateService(preferencesStore: preferencesStore)
        let viewModel = PreferencesViewModel(
            preferencesStore: preferencesStore,
            channelStore: channelStore,
            notificationService: resolvedService,
            updateService: resolvedUpdateService,
            onFactoryReset: onFactoryReset,
            onUpdateAvailable: { [weak preferencesStore, weak self] release in
                guard let preferencesStore else { return }
                UpdateAvailableWindowController.show(
                    release: release,
                    preferencesStore: preferencesStore,
                    onVisibilityChange: self?.onUpdateVisibilityChange
                )
            },
            onRestore: onRestore
        )
        let rootView = PreferencesView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)
        window.contentViewController = hostingController
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func notifyClosed() {
        let callback = onVisibilityChange
        onVisibilityChange = nil
        callback?(false)
    }

    public override func close() {
        super.close()
        notifyClosed()
    }

    public func windowWillClose(_ notification: Notification) {
        notifyClosed()
        if PreferencesWindowController.currentController === self {
            PreferencesWindowController.currentController = nil
        }
    }
}
