import AppKit
import SwiftUI

/// High-contrast branded monogram placeholder for avatars when local image files are missing or loading.
public struct WidgetMonogramView: View {
    public let displayName: String
    public let size: CGFloat
    public let isDimmed: Bool

    public init(displayName: String, size: CGFloat = 36, isDimmed: Bool = false) {
        self.displayName = displayName
        self.size = size
        self.isDimmed = isDimmed
    }

    public var letter: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "V"
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: isDimmed
                    ? [Color(white: 0.25), Color(white: 0.12)]
                    : [Theme.accent, Color.purple.opacity(0.8), Color.black.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .saturation(isDimmed ? 0.2 : 1.0)
            .opacity(isDimmed ? 0.6 : 1.0)

            Text(letter)
                .font(.system(size: size * 0.48, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(isDimmed ? 0.2 : 0.35), lineWidth: 1)
        )
    }
}

/// Helper that resolves cached avatar files from the container avatars directory.
public enum WidgetAvatarLoader {
    public static func loadNSImage(filename: String?, in directoryURL: URL?) -> NSImage? {
        guard let filename = filename?.trimmingCharacters(in: .whitespacesAndNewlines),
              !filename.isEmpty,
              let directoryURL = directoryURL else {
            return nil
        }
        let fileURL = directoryURL.appendingPathComponent(filename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return NSImage(contentsOf: fileURL)
    }
}
