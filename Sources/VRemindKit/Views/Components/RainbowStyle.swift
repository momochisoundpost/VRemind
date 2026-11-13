import SwiftUI

public enum RainbowPalette {
    public static let colors: [Color] = [
        Color(red: 1.0, green: 0.0, blue: 0.333),   // #FF0055
        Color(red: 1.0, green: 0.6, blue: 0.0),     // #FF9900
        Color(red: 1.0, green: 0.902, blue: 0.0),   // #FFE600
        Color(red: 0.2, green: 0.8, blue: 0.2),     // #33CC33
        Color(red: 0.0, green: 0.749, blue: 1.0),   // #00BFFF
        Color(red: 0.6, green: 0.2, blue: 1.0),     // #9933FF
        Color(red: 1.0, green: 0.0, blue: 0.333)    // #FF0055
    ]
}

public struct RainbowGradientView: View {
    public let reduceMotion: Bool

    public init(reduceMotion: Bool = false) {
        self.reduceMotion = reduceMotion
    }

    public var body: some View {
        TimelineView(.animation) { context in
            let cycleDuration = reduceMotion ? 10.0 : 3.0
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
            let shift = CGFloat(phase) * 2.0 - 1.0

            LinearGradient(
                gradient: Gradient(colors: RainbowPalette.colors),
                startPoint: UnitPoint(x: shift, y: 0.0),
                endPoint: UnitPoint(x: shift + 1.0, y: 1.0)
            )
        }
    }
}

public struct RainbowTextModifier: ViewModifier {
    public let active: Bool
    public let reduceMotion: Bool

    public init(active: Bool, reduceMotion: Bool = false) {
        self.active = active
        self.reduceMotion = reduceMotion
    }

    public func body(content: Content) -> some View {
        if active {
            content
                .hidden()
                .overlay(
                    RainbowGradientView(reduceMotion: reduceMotion)
                        .mask(content)
                )
        } else {
            content
        }
    }
}

extension View {
    public func rainbowForeground(active: Bool, reduceMotion: Bool = false) -> some View {
        modifier(RainbowTextModifier(active: active, reduceMotion: reduceMotion))
    }
}
