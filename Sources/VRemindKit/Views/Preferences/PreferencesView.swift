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
    @Published public var isShowingResetConfirmation: Bool = false
    @Published public private(set) var authorizationStatus: UNAuthorizationStatus

    private let onFactoryReset: (() -> Void)?

    public init(
        preferencesStore: PreferencesStore,
        channelStore: ChannelStore,
        notificationService: NotificationService? = nil,
        onFactoryReset: (() -> Void)? = nil
    ) {
        self.preferencesStore = preferencesStore
        self.channelStore = channelStore
        self.notificationService = notificationService
        self.onFactoryReset = onFactoryReset
        self.authorizationStatus = notificationService?.authorizationStatus ?? .notDetermined
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
        .frame(width: 480, height: 320)
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

            Spacer()
        }
        .padding(20)
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

            Spacer()
        }
        .padding(20)
        .onAppear {
            Task {
                await viewModel.refreshNotificationStatus()
            }
        }
    }

    // MARK: - Tab 3: About

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .frame(width: 54, height: 54)
                Image(systemName: "play.tv")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(Theme.accent)
            }

            VStack(spacing: 4) {
                Text("VRemind")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Version 1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(PreferencesViewModel.attributionCopy)
                .font(.callout)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Text(PreferencesViewModel.forkCopy)
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

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
            .buttonStyle(.bordered)
            .padding(.top, 4)

            Spacer()
        }
        .padding(20)
    }
}
