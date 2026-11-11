import AppKit
import SwiftUI
import VRemindKit

@MainActor
public final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private static var currentController: PreferencesWindowController?

    public static func show(
        preferencesStore: PreferencesStore,
        channelStore: ChannelStore,
        notificationService: NotificationService? = nil,
        onFactoryReset: (() -> Void)? = nil
    ) {
        if let existing = currentController {
            existing.window?.center()
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = PreferencesWindowController(
            preferencesStore: preferencesStore,
            channelStore: channelStore,
            notificationService: notificationService,
            onFactoryReset: onFactoryReset
        )
        currentController = controller
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        onFactoryReset: (() -> Void)? = nil
    ) {
        let viewModel = PreferencesViewModel(
            preferencesStore: preferencesStore,
            channelStore: channelStore,
            notificationService: notificationService,
            onFactoryReset: onFactoryReset
        )
        let rootView = PreferencesView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func windowWillClose(_ notification: Notification) {
        if PreferencesWindowController.currentController === self {
            PreferencesWindowController.currentController = nil
        }
    }
}
