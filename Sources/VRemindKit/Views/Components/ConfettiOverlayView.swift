import SwiftUI

public struct ConfettiOverlayView: View {
    private enum ParticleShape: CaseIterable {
        case rectangle
        case circle
        case streamer
    }

    private struct Particle {
        let initialX: CGFloat
        let initialY: CGFloat
        let speed: CGFloat
        let swayAmplitude: CGFloat
        let swayFrequency: CGFloat
        let swayPhase: CGFloat
        let rotationSpeed: Double
        let initialRotation: Double
        let width: CGFloat
        let height: CGFloat
        let shape: ParticleShape
        let color: Color
    }

    private let particles: [Particle]
    private let startDate = Date()

    public init() {
        let palette = RainbowPalette.colors.dropLast()
        let shapes = ParticleShape.allCases
        self.particles = (0..<45).map { index in
            let seed = Double(index)
            let normX = CGFloat((sin(seed * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1.0))
            let normY = CGFloat((cos(seed * 78.233) * 43758.5453).truncatingRemainder(dividingBy: 1.0))
            return Particle(
                initialX: abs(normX),
                initialY: abs(normY),
                speed: 0.14 + CGFloat(index % 5) * 0.035,
                swayAmplitude: 8.0 + CGFloat(index % 4) * 4.0,
                swayFrequency: 1.5 + CGFloat(index % 3) * 0.6,
                swayPhase: CGFloat(index) * 0.45,
                rotationSpeed: (index % 2 == 0 ? 1.0 : -1.0) * (1.2 + Double(index % 4) * 0.5),
                initialRotation: Double(index) * 0.7,
                width: index % 3 == 2 ? 3.5 : CGFloat(5 + (index % 4)),
                height: index % 3 == 2 ? 12.0 : CGFloat(4 + (index % 3)),
                shape: shapes[index % shapes.count],
                color: palette[index % palette.count]
            )
        }
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(startDate))
            Canvas { context, size in
                guard size.width > 0, size.height > 0 else { return }

                for particle in particles {
                    let progress = (particle.initialY + CGFloat(elapsed) * particle.speed)
                        .truncatingRemainder(dividingBy: 1.0)
                    let y = progress * (size.height + 24.0) - 12.0
                    let sway = sin(CGFloat(elapsed) * particle.swayFrequency + particle.swayPhase) * particle.swayAmplitude
                    let x = particle.initialX * size.width + sway
                    let angle = Angle.radians(particle.initialRotation + elapsed * particle.rotationSpeed)

                    var particleContext = context
                    particleContext.translateBy(x: x, y: y)
                    particleContext.rotate(by: angle)

                    let rect = CGRect(
                        x: -particle.width / 2.0,
                        y: -particle.height / 2.0,
                        width: particle.width,
                        height: particle.height
                    )

                    let path: Path
                    switch particle.shape {
                    case .rectangle, .streamer:
                        path = Path(rect)
                    case .circle:
                        path = Path(ellipseIn: rect)
                    }

                    particleContext.fill(path, with: .color(particle.color.opacity(0.85)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
