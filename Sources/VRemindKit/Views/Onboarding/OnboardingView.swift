import SwiftUI
import UserNotifications

@MainActor
public final class OnboardingViewModel: ObservableObject {
    @Published public var customHandle: String = "@bukancaitlyn"
    @Published public private(set) var validationError: String? = nil
    @Published public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let channelStore: ChannelStore
    private let preferencesStore: PreferencesStore
    private let notificationService: NotificationService?
    private let onComplete: (() -> Void)?

    public init(
        channelStore: ChannelStore,
        preferencesStore: PreferencesStore,
        notificationService: NotificationService? = nil,
        onComplete: (() -> Void)? = nil
    ) {
        self.channelStore = channelStore
        self.preferencesStore = preferencesStore
        self.notificationService = notificationService
        self.onComplete = onComplete
        self.authorizationStatus = notificationService?.authorizationStatus ?? .notDetermined
    }

    public func requestNotifications() async {
        if let notificationService {
            _ = await notificationService.requestAuthorization()
            self.authorizationStatus = notificationService.authorizationStatus
        }
    }

    @discardableResult
    public func completeOnboarding() -> Bool {
        let trimmed = customHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            validationError = nil
            ensureDefaultChannel()
        } else {
            guard let normalized = WatchedChannel.normalizeHandle(trimmed) else {
                validationError = "Please enter a valid YouTube handle (e.g. @channel)"
                return false
            }
            validationError = nil

            if normalized.lowercased() == "@bukancaitlyn" {
                ensureDefaultChannel()
            } else {
                if channelStore.channels.count == 1 && channelStore.channels.first?.id.lowercased() == "@bukancaitlyn" {
                    channelStore.removeChannel(id: "@bukancaitlyn")
                    channelStore.addChannel(handle: normalized, name: nil, avatarURL: nil)
                } else {
                    channelStore.addChannel(handle: normalized, name: nil, avatarURL: nil)
                }
            }
        }

        preferencesStore.settings.hasCompletedOnboarding = true
        onComplete?()
        return true
    }

    private func ensureDefaultChannel() {
        if !channelStore.channels.contains(where: { $0.id.lowercased() == "@bukancaitlyn" }) {
            channelStore.addChannel(handle: "@bukancaitlyn", name: "Caitlyn Momochi", avatarURL: nil)
        }
    }
}

public struct OnboardingView: View {
    @ObservedObject public var viewModel: OnboardingViewModel

    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.18))
                        .frame(width: 56, height: 56)
                    Image(systemName: "play.tv")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(Theme.accent)
                }

                Text("Welcome to VRemind")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Never miss a stream from your favorite VTuber")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)

            Divider()

            // Channel Input
            VStack(alignment: .leading, spacing: 6) {
                Text("Favorite VTuber")
                    .font(.headline)

                TextField("@handle", text: $viewModel.customHandle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.completeOnboarding()
                    }

                if let error = viewModel.validationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Text("Enter a YouTube handle starting with @ (defaults to @bukancaitlyn).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Notification Permission
            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications")
                    .font(.headline)

                HStack {
                    Button(action: {
                        Task {
                            await viewModel.requestNotifications()
                        }
                    }) {
                        Label("Enable Notifications", systemImage: "bell.badge")
                    }
                    .disabled(viewModel.authorizationStatus == .authorized)

                    Spacer()

                    HStack(spacing: 4) {
                        switch viewModel.authorizationStatus {
                        case .authorized, .provisional:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Enabled")
                                .foregroundColor(.green)
                        case .denied:
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Disabled in Settings")
                                .foregroundColor(.secondary)
                        default:
                            Image(systemName: "bell.slash")
                                .foregroundColor(.secondary)
                            Text("Not Enabled")
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.caption)
                }
            }

            Spacer(minLength: 8)

            // Get Started Button
            Button(action: {
                viewModel.completeOnboarding()
            }) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 440, height: 380)
    }
}
