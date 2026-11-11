import SwiftUI

public struct ChannelAvatarView: View {
    public let url: URL?
    public let size: CGFloat
    public let fallbackSymbol: String

    public init(url: URL?, size: CGFloat = 36, fallbackSymbol: String = "sparkles") {
        self.url = url
        self.size = size
        self.fallbackSymbol = fallbackSymbol
    }

    public var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
                    )
            default:
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.18))
                        .frame(width: size, height: size)
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .frame(width: size, height: size)
    }
}
