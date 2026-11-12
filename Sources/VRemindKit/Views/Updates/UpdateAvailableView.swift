import AppKit
import SwiftUI

public struct UpdateAvailableView: View {
    public let release: GitHubRelease
    public let currentVersion: String
    public let onDownload: () -> Void
    public let onSkip: () -> Void
    public let onLater: () -> Void

    public init(
        release: GitHubRelease,
        currentVersion: String = AppConstants.appVersion,
        onDownload: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        onLater: @escaping () -> Void
    ) {
        self.release = release
        self.currentVersion = currentVersion
        self.onDownload = onDownload
        self.onSkip = onSkip
        self.onLater = onLater
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(alignment: .center, spacing: 14) {
                AppIconView(size: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("VRemind \(release.tagName) is available!")
                        .font(.headline)
                        .fontWeight(.bold)

                    Text("Current version: \(currentVersion) • New version: \(release.tagName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Release Notes
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let body = release.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(LocalizedStringKey(body))
                            .font(.system(.body, design: .default))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else {
                        Text("No release notes provided.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            // Actions
            HStack(spacing: 12) {
                Button(action: onSkip) {
                    Text("Skip This Version")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: onLater) {
                    Text("Remind Me Later")
                }
                .buttonStyle(.borderless)

                Button(action: onDownload) {
                    Text("Download Update")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 400)
    }
}
