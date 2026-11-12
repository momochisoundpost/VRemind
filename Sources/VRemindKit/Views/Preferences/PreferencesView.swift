import AppKit
import SwiftUI
import UserNotifications

@MainActor
public final class PreferencesViewModel: ObservableObject {
    public nonisolated static let attributionCopy = "VRemind by Caitlyn Momochi, initially vibecoded for their Hackintosh video"
    public nonisolated static let forkCopy = "You don't like what I did? Go fork yourself, it's free and open source."

    public let preferencesStore: PreferencesStore
    public let channelStore: ChannelStore
    public let notificationService: NotificationService?
    public let updateService: UpdateService?
    public let onUpdateAvailable: ((GitHubRelease) -> Void)?

    @Published public var isShowingResetConfirmation: Bool = false
    @Published public var isShowingEasterEggAlert: Bool = false
    @Published public var updateStatusText: String? = nil
    @Published public var isCheckingUpdates: Bool = false
    @Published public var latestAvailableRelease: GitHubRelease? = nil
    @Published public private(set) var authorizationStatus: UNAuthorizationStatus

    private let onFactoryReset: (() -> Void)?

    public var isAutoUpdateEnabled: Bool {
        get {
            preferencesStore.settings.updateConsent == .allowed
        }
        set {
            setAutoUpdateEnabled(newValue)
        }
    }

    public init(
        preferencesStore: PreferencesStore,
        channelStore: ChannelStore,
        notificationService: NotificationService? = nil,
        updateService: UpdateService? = nil,
        onFactoryReset: (() -> Void)? = nil,
        onUpdateAvailable: ((GitHubRelease) -> Void)? = nil
    ) {
        self.preferencesStore = preferencesStore
        self.channelStore = channelStore
        self.notificationService = notificationService
        self.updateService = updateService
        self.onFactoryReset = onFactoryReset
        self.onUpdateAvailable = onUpdateAvailable
        self.authorizationStatus = notificationService?.authorizationStatus ?? .notDetermined
    }

    public convenience init(
        preferencesStore: PreferencesStore,
        channelStore: ChannelStore,
        onFactoryReset: (() -> Void)? = nil
    ) {
        self.init(
            preferencesStore: preferencesStore,
            channelStore: channelStore,
            notificationService: NotificationService(),
            updateService: nil,
            onFactoryReset: onFactoryReset,
            onUpdateAvailable: nil
        )
    }

    public func setAutoUpdateEnabled(_ enabled: Bool) {
        preferencesStore.settings.updateConsent = enabled ? .allowed : .neverAsk
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        preferencesStore.settings.launchAtLogin = enabled
        _ = LaunchAtLoginHelper.setEnabled(enabled)
    }

    public func performFactoryReset() {
        preferencesStore.resetToDefaults()
        channelStore.resetToDefaults()
        _ = LaunchAtLoginHelper.setEnabled(false)
        isShowingResetConfirmation = false
        onFactoryReset?()
    }

    public func requestNotifications() async {
        if let notificationService {
            _ = await notificationService.requestAuthorization()
            self.authorizationStatus = notificationService.authorizationStatus
        }
    }

    public func refreshNotificationStatus() async {
        if let notificationService {
            self.authorizationStatus = await notificationService.refreshAuthorizationStatus()
        }
    }

    public func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            LinkOpener.open(url)
        }
    }

    @discardableResult
    public func checkForUpdatesManually() async -> UpdateCheckResult? {
        guard let updateService else {
            updateStatusText = "Update service unavailable"
            return nil
        }

        isCheckingUpdates = true
        updateStatusText = "Checking for updates..."
        defer { isCheckingUpdates = false }

        let result = await updateService.checkForUpdates(manual: true)
        switch result {
        case .updateAvailable(let release):
            latestAvailableRelease = release
            updateStatusText = "Version \(release.tagName) is available."
            onUpdateAvailable?(release)
        case .upToDate(let latestVersion):
            latestAvailableRelease = nil
            updateStatusText = "VRemind is up to date (\(latestVersion))."
        case .localVersionNewer(let remoteVersion):
            latestAvailableRelease = nil
            isShowingEasterEggAlert = true
            updateStatusText = "Local version is newer than GitHub (\(remoteVersion))."
        case .skippedIgnored(let version):
            latestAvailableRelease = nil
            updateStatusText = "Version \(version) is available (ignored)."
        case .skippedNotConsented:
            latestAvailableRelease = nil
            updateStatusText = "Automatic updates are disabled."
        case .failed(let message):
            latestAvailableRelease = nil
            updateStatusText = "Update check failed: \(message)"
        }
        return result
    }
}

public struct PreferencesView: View {
    @ObservedObject public var viewModel: PreferencesViewModel
    @ObservedObject private var preferencesStore: PreferencesStore

    public init(viewModel: PreferencesViewModel) {
        self.viewModel = viewModel
        self.preferencesStore = viewModel.preferencesStore
    }

    public var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)

            notificationsTab
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .tag(1)

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(2)
        }
        .frame(width: 480, height: 400)
    }

    // MARK: - Tab 1: General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Startup")
                    .font(.headline)

                Toggle(
                    "Launch VRemind at login",
                    isOn: Binding(
                        get: { preferencesStore.settings.launchAtLogin },
                        set: { viewModel.setLaunchAtLogin($0) }
                    )
                )
                .toggleStyle(.checkbox)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Updates")
                    .font(.headline)

                Text("Current Version: \(AppConstants.appVersion)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Toggle(
                    "Automatically check for updates",
                    isOn: Binding(
                        get: { viewModel.isAutoUpdateEnabled },
                        set: { viewModel.setAutoUpdateEnabled($0) }
                    )
                )
                .toggleStyle(.checkbox)

                HStack(spacing: 12) {
                    Button("Check for Updates Now") {
                        Task {
                            await viewModel.checkForUpdatesManually()
                        }
                    }
                    .disabled(viewModel.isCheckingUpdates)

                    if viewModel.isCheckingUpdates {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let statusText = viewModel.updateStatusText {
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .alert(isPresented: $viewModel.isShowingEasterEggAlert) {
                Alert(
                    title: Text("Did you steal Caitlyn's computer?"),
                    message: Text("Your version (\(AppConstants.appVersion)) is newer than what's available on GitHub."),
                    primaryButton: .default(Text("Yes")) {
                        LinkOpener.open(AppConstants.policeSirenURL)
                    },
                    secondaryButton: .cancel(Text("No"))
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Danger Zone")
                    .font(.headline)
                    .foregroundColor(.red)

                Text("Reset all watchlist channels, alert preferences, and login items to factory defaults.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Reset All Data to Factory Defaults...") {
                    viewModel.isShowingResetConfirmation = true
                }
                .buttonStyle(.bordered)
            }
            .alert(isPresented: $viewModel.isShowingResetConfirmation) {
                Alert(
                    title: Text("Reset All Data?"),
                    message: Text("This will restore default settings, reset your watchlist back to @bukancaitlyn, and disable launch at login. This action cannot be undone."),
                    primaryButton: .destructive(Text("Reset")) {
                        viewModel.performFactoryReset()
                    },
                    secondaryButton: .cancel()
                )
            }

            Spacer()
        }
        .padding(20)
    }

    // MARK: - Tab 2: Notifications

    private var notificationsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stream Alerts")
                    .font(.headline)

                Toggle("Notify when a stream goes live on air", isOn: $preferencesStore.settings.notifyOnLive)
                    .toggleStyle(.checkbox)

                Toggle("Notify when an upcoming stream / waiting room appears", isOn: $preferencesStore.settings.notifyOnUpcoming)
                    .toggleStyle(.checkbox)

                Toggle("Play sound with notifications", isOn: $preferencesStore.settings.playNotificationSound)
                    .toggleStyle(.checkbox)
            }

            if viewModel.notificationService != nil {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Notification Permission")
                        .font(.headline)

                    HStack {
                        switch viewModel.authorizationStatus {
                        case .authorized, .provisional:
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Notifications Enabled")
                            }
                        case .denied:
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Notifications disabled in System Settings")
                            }

                            Spacer()

                            Button("Open System Settings") {
                                viewModel.openSystemNotificationSettings()
                            }
                        default:
                            HStack(spacing: 6) {
                                Image(systemName: "bell.slash")
                                    .foregroundColor(.secondary)
                                Text("Notifications Not Enabled")
                            }

                            Spacer()

                            Button("Enable Notifications") {
                                Task {
                                    await viewModel.requestNotifications()
                                }
                            }
                        }
                    }
                    .font(.subheadline)
                }
            }

            Spacer()
        }
        .padding(20)
        .onAppear {
            if viewModel.notificationService != nil {
                Task {
                    await viewModel.refreshNotificationStatus()
                }
            }
        }
    }

    // MARK: - Tab 3: About

    private var aboutTab: some View {
        VStack(spacing: 10) {
            Spacer()

            AppIconView(size: 54)

            VStack(spacing: 4) {
                Text("VRemind")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Version \(AppConstants.appVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(PreferencesViewModel.attributionCopy)
                .font(.callout)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)

            Text(PreferencesViewModel.forkCopy)
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button(action: {
                        LinkOpener.open(AppConstants.youtubeChannelURL)
                    }) {
                        Label("YouTube", systemImage: "play.rectangle.fill")
                    }

                    Button(action: {
                        LinkOpener.open(AppConstants.twitterURL)
                    }) {
                        Label("Twitter/X", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                }

                HStack(spacing: 12) {
                    Button(action: {
                        LinkOpener.open(AppConstants.githubURL)
                    }) {
                        Label {
                            Text("GitHub")
                        } icon: {
                            Image(nsImage: BrandIcon.githubImage)
                        }
                    }

                    Button(action: {
                        LinkOpener.open(AppConstants.instagramURL)
                    }) {
                        Label {
                            Text("Instagram")
                        } icon: {
                            Image(nsImage: BrandIcon.instagramImage)
                        }
                    }
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)

            Spacer()
        }
        .padding(20)
    }
}
