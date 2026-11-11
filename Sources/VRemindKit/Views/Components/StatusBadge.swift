import SwiftUI

public struct StatusBadge: View {
    public let isLive: Bool
    @State private var isPulsing = false

    public init(isLive: Bool) {
        self.isLive = isLive
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isLive ? Theme.live : Color.secondary.opacity(0.6))
                .frame(width: 8, height: 8)
                .scaleEffect(isLive && isPulsing ? 1.25 : 1.0)
                .opacity(isLive && isPulsing ? 0.65 : 1.0)
                .animation(
                    isLive
                        ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )

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
        .onAppear {
            isPulsing = isLive
        }
        .onChange(of: isLive) { newValue in
            isPulsing = newValue
        }
    }
}
