import AppKit
import SwiftUI
import VRemindKit

@MainActor
public final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private static var currentController: OnboardingWindowController?

    public static func showIfNeeded(
        channelStore: ChannelStore,
        preferencesStore: PreferencesStore,
        notificationService: NotificationService,
        onComplete: (() -> Void)? = nil
    ) {
        guard !preferencesStore.settings.hasCompletedOnboarding else {
            return
        }

        if let existing = currentController {
            existing.window?.center()
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = OnboardingWindowController(
            channelStore: channelStore,
            preferencesStore: preferencesStore,
            notificationService: notificationService,
            onComplete: {
                onComplete?()
                currentController?.close()
                currentController = nil
            }
        )
        currentController = controller
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public init(
        channelStore: ChannelStore,
        preferencesStore: PreferencesStore,
        notificationService: NotificationService,
        onComplete: (() -> Void)? = nil
    ) {
        let viewModel = OnboardingViewModel(
            channelStore: channelStore,
            preferencesStore: preferencesStore,
            notificationService: notificationService,
            onComplete: onComplete
        )
        let rootView = OnboardingView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to VRemind"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentViewController = hostingController

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func windowWillClose(_ notification: Notification) {
        if OnboardingWindowController.currentController === self {
            OnboardingWindowController.currentController = nil
        }
    }
}
