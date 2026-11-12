import AppKit
import SwiftUI
import VRemindKit

@MainActor
public final class UpdateAvailableWindowController: NSWindowController, NSWindowDelegate {
    private static var currentController: UpdateAvailableWindowController?

    public let release: GitHubRelease
    public let preferencesStore: PreferencesStore

    public static func show(
        release: GitHubRelease,
        preferencesStore: PreferencesStore,
        openURL: ((URL) -> Void)? = nil
    ) {
        if let existing = currentController {
            if existing.release.tagName == release.tagName {
                existing.window?.center()
                existing.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            } else {
                existing.close()
                currentController = nil
            }
        }

        let controller = UpdateAvailableWindowController(
            release: release,
            preferencesStore: preferencesStore,
            openURL: openURL
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
        release: GitHubRelease,
        preferencesStore: PreferencesStore,
        openURL: ((URL) -> Void)? = nil
    ) {
        self.release = release
        self.preferencesStore = preferencesStore

        let opener = openURL ?? LinkOpener.open

        var controllerRef: UpdateAvailableWindowController?

        let rootView = UpdateAvailableView(
            release: release,
            currentVersion: AppConstants.appVersion,
            onDownload: {
                let zipAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })
                let targetURL = zipAsset?.browserDownloadURL ?? release.htmlURL
                opener(targetURL)
                controllerRef?.close()
                if UpdateAvailableWindowController.currentController === controllerRef {
                    UpdateAvailableWindowController.currentController = nil
                }
            },
            onSkip: {
                preferencesStore.settings.ignoredUpdateTag = release.tagName
                controllerRef?.close()
                if UpdateAvailableWindowController.currentController === controllerRef {
                    UpdateAvailableWindowController.currentController = nil
                }
            },
            onLater: {
                controllerRef?.close()
                if UpdateAvailableWindowController.currentController === controllerRef {
                    UpdateAvailableWindowController.currentController = nil
                }
            }
        )

        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Software Update Available"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController

        super.init(window: window)
        controllerRef = self
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func windowWillClose(_ notification: Notification) {
        if UpdateAvailableWindowController.currentController === self {
            UpdateAvailableWindowController.currentController = nil
        }
    }
}
