import SwiftUI

public struct StatusBadge: View {
    public let isLive: Bool

    public init(isLive: Bool) {
        self.isLive = isLive
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isLive ? Theme.live : Color.secondary.opacity(0.6))
                .frame(width: 8, height: 8)

            Text(isLive ? "LIVE NOW" : "OFFLINE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isLive ? Theme.live : .secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isLive ? Theme.live.opacity(0.14) : Color.secondary.opacity(0.12))
        )
        .overlay(
            Capsule()
                .strokeBorder(isLive ? Theme.live.opacity(0.35) : Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}
