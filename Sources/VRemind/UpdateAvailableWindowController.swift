import AppKit
import SwiftUI
import VRemindKit

@MainActor
public final class UpdateAvailableWindowController: NSWindowController, NSWindowDelegate {
    private static var currentController: UpdateAvailableWindowController?

    public let release: GitHubRelease
    public let preferencesStore: PreferencesStore
    private var onVisibilityChange: ((Bool) -> Void)?

    public static func show(
        release: GitHubRelease,
        preferencesStore: PreferencesStore,
        openURL: ((URL) -> Void)? = nil,
        onVisibilityChange: ((Bool) -> Void)? = nil
    ) {
        if let existing = currentController {
            if existing.release.tagName == release.tagName {
                if let onVisibilityChange {
                    existing.onVisibilityChange = onVisibilityChange
                }
                existing.window?.center()
                existing.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                existing.onVisibilityChange?(true)
                return
            } else {
                existing.close()
                currentController = nil
            }
        }

        let controller = UpdateAvailableWindowController(
            release: release,
            preferencesStore: preferencesStore,
            openURL: openURL,
            onVisibilityChange: onVisibilityChange
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
        release: GitHubRelease,
        preferencesStore: PreferencesStore,
        openURL: ((URL) -> Void)? = nil,
        onVisibilityChange: ((Bool) -> Void)? = nil
    ) {
        self.release = release
        self.preferencesStore = preferencesStore
        self.onVisibilityChange = onVisibilityChange

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Software Update Available"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        let opener = openURL ?? LinkOpener.open

        let rootView = UpdateAvailableView(
            release: release,
            currentVersion: AppConstants.appVersion,
            onDownload: { [weak self] in
                guard let self else { return }
                let zipAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })
                let targetURL = zipAsset?.browserDownloadURL ?? release.htmlURL
                opener(targetURL)
                self.close()
                if UpdateAvailableWindowController.currentController === self {
                    UpdateAvailableWindowController.currentController = nil
                }
            },
            onSkip: { [weak self] in
                guard let self else { return }
                preferencesStore.settings.ignoredUpdateTag = release.tagName
                self.close()
                if UpdateAvailableWindowController.currentController === self {
                    UpdateAvailableWindowController.currentController = nil
                }
            },
            onLater: { [weak self] in
                guard let self else { return }
                self.close()
                if UpdateAvailableWindowController.currentController === self {
                    UpdateAvailableWindowController.currentController = nil
                }
            }
        )

        window.contentViewController = NSHostingController(rootView: rootView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func teardownAndNotifyClosed() {
        window?.contentViewController = nil
        let callback = onVisibilityChange
        onVisibilityChange = nil
        callback?(false)
    }

    public override func close() {
        teardownAndNotifyClosed()
        super.close()
    }

    public func windowWillClose(_ notification: Notification) {
        teardownAndNotifyClosed()
        if UpdateAvailableWindowController.currentController === self {
            UpdateAvailableWindowController.currentController = nil
        }
    }
}
