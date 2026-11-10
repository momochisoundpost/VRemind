import SwiftUI

public struct CheatCodeTracker: Sendable {
    public static let defaultCode = "jemarijembut"

    public let targetCode: String
    private var buffer: String = ""

    public init(targetCode: String = Self.defaultCode) {
        self.targetCode = targetCode.lowercased()
    }

    public mutating func feed(_ characters: String) -> Bool {
        let filtered = characters.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !filtered.isEmpty else { return false }
        buffer.append(filtered)
        if buffer.count > targetCode.count * 2 {
            buffer = String(buffer.suffix(targetCode.count))
        }
        if buffer.hasSuffix(targetCode) {
            buffer = ""
            return true
        }
        return false
    }

    public mutating func reset() {
        buffer = ""
    }
}

public struct ShakeEffect: GeometryEffect {
    public var animatableData: CGFloat

    public init(shakes: CGFloat) {
        self.animatableData = shakes
    }

    public func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 9 * sin(animatableData * .pi * 2)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

public struct EasterEggParticle: Identifiable, Sendable {
    public enum Kind: Sendable {
        case waveEmoji
        case confetti(Color, Bool)
    }

    public let id: Int
    public let kind: Kind
    public let startXFraction: Double
    public let driftX: Double
    public let startDelay: Double
    public let fallDuration: Double
    public let spinSpeed: Double
    public let scale: Double
}

public struct EasterEggOverlayView: View {
    public let startDate: Date
    private let particles: [EasterEggParticle]

    private static let confettiColors: [Color] = [
        Color(red: 0.62, green: 0.35, blue: 0.92),
        Color(red: 0.98, green: 0.28, blue: 0.48),
        Color(red: 0.22, green: 0.82, blue: 0.96),
        Color(red: 1.00, green: 0.80, blue: 0.20),
        Color(red: 0.35, green: 0.92, blue: 0.55)
    ]

    public init(startDate: Date) {
        self.startDate = startDate
        var generated: [EasterEggParticle] = []
        for idx in 0..<42 {
            let isEmoji = (idx % 3 == 0)
            let kind: EasterEggParticle.Kind
            if isEmoji {
                kind = .waveEmoji
            } else {
                let color = Self.confettiColors[idx % Self.confettiColors.count]
                kind = .confetti(color, idx.isMultiple(of: 2))
            }
            let xFrac = Double((idx * 37) % 100) / 100.0
            let drift = Double(((idx * 53) % 60) - 30)
            let delay = Double((idx * 19) % 70) / 100.0
            let duration = 1.45 + Double((idx * 29) % 85) / 100.0
            let spin = Double(((idx * 41) % 360) - 180) * 2.2
            let scale = isEmoji ? (0.85 + Double(idx % 5) * 0.12) : (0.8 + Double(idx % 4) * 0.15)
            generated.append(
                EasterEggParticle(
                    id: idx,
                    kind: kind,
                    startXFraction: xFrac,
                    driftX: drift,
                    startDelay: delay,
                    fallDuration: duration,
                    spinSpeed: spin,
                    scale: scale
                )
            )
        }
        self.particles = generated
    }

    public var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                let elapsed = context.date.timeIntervalSince(startDate)
                ZStack {
                    ForEach(particles) { particle in
                        let localTime = elapsed - particle.startDelay
                        if localTime >= 0 && localTime <= particle.fallDuration {
                            let progress = localTime / particle.fallDuration
                            let x = particle.startXFraction * geo.size.width + particle.driftX * sin(progress * .pi * 2)
                            let y = -24 + progress * (geo.size.height + 48)
                            let opacity = progress > 0.8 ? max(0, (1.0 - progress) / 0.2) : 1.0

                            particleView(for: particle)
                                .scaleEffect(particle.scale)
                                .rotationEffect(.degrees(localTime * particle.spinSpeed))
                                .position(x: x, y: y)
                                .opacity(opacity)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func particleView(for particle: EasterEggParticle) -> some View {
        switch particle.kind {
        case .waveEmoji:
            Text("👋")
                .font(.system(size: 20))
        case let .confetti(color, isCircle):
            if isCircle {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 9, height: 5)
            }
        }
    }
}
