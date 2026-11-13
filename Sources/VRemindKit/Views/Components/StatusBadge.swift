import SwiftUI

public struct StatusBadge: View {
    public let isLive: Bool
    public let label: String?
    public let isCelebration: Bool
    public let reduceMotion: Bool

    public init(
        isLive: Bool,
        label: String? = nil,
        isCelebration: Bool = false,
        reduceMotion: Bool = false
    ) {
        self.isLive = isLive
        self.label = label
        self.isCelebration = isCelebration
        self.reduceMotion = reduceMotion
    }

    public var body: some View {
        let displayLabel = label ?? (isLive ? "LIVE NOW" : "OFFLINE")

        HStack(spacing: 6) {
            Circle()
                .fill(isLive ? Theme.live : Color.secondary.opacity(0.6))
                .frame(width: 8, height: 8)
                .rainbowForeground(active: isCelebration, reduceMotion: reduceMotion)

            Text(displayLabel)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isLive ? Theme.live : .secondary)
                .rainbowForeground(active: isCelebration, reduceMotion: reduceMotion)
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
                .rainbowForeground(active: isCelebration, reduceMotion: reduceMotion)
        )
    }
}
