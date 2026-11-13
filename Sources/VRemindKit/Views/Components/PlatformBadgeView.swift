import SwiftUI

/// Shared platform badge view displaying a solid colored dot identifying the stream platform (YouTube red, Twitch purple).
/// Styled with a subtle dark border ring so it pops cleanly against both light and dark avatars.
public struct PlatformBadgeView: View {
    public let platform: StreamPlatform
    public let size: CGFloat

    public init(platform: StreamPlatform, size: CGFloat = 10) {
        self.platform = platform
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(Theme.platformColor(for: platform))
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(0.75), lineWidth: 1.5)
            )
            .accessibilityLabel(platform.displayName)
    }
}
