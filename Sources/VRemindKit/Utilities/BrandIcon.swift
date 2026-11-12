import AppKit
import SwiftUI

public enum BrandIcon {
    public static let githubSVG = """
    <svg role="img" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
      <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z"/>
    </svg>
    """

    public static let instagramSVG = """
    <svg role="img" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
      <path d="M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zm0-2.163c-3.259 0-3.667.014-4.947.072-4.358.2-6.78 2.618-6.98 6.98-.059 1.281-.073 1.689-.073 4.948 0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98 1.281.058 1.689.072 4.948.072 3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98-1.281-.059-1.69-.073-4.949-.073zm0 5.838c-3.403 0-6.162 2.759-6.162 6.162s2.759 6.163 6.162 6.163 6.162-2.759 6.162-6.163c0-3.403-2.759-6.162-6.162-6.162zm0 10.162c-2.209 0-4-1.79-4-4 0-2.209 1.791-4 4-4s4 1.791 4 4c0 2.21-1.791 4-4 4zm6.406-11.845c-.796 0-1.441.645-1.441 1.44s.645 1.44 1.441 1.44c.795 0 1.439-.645 1.439-1.44s-.644-1.44-1.439-1.44z"/>
    </svg>
    """

    public static func nsImage(named name: String, fallbackSVG: String) -> NSImage {
        let bundle = Bundle.main
        if let bundleURL = bundle.url(forResource: name, withExtension: "svg", subdirectory: "Icons") ??
                           bundle.url(forResource: name, withExtension: "svg"),
           let img = NSImage(contentsOf: bundleURL) {
            img.isTemplate = true
            img.size = NSSize(width: 14, height: 14)
            return img
        }
        if let data = fallbackSVG.data(using: .utf8), let img = NSImage(data: data) {
            img.isTemplate = true
            img.size = NSSize(width: 14, height: 14)
            return img
        }
        return NSImage()
    }

    public static var githubImage: NSImage {
        nsImage(named: "github", fallbackSVG: githubSVG)
    }

    public static var instagramImage: NSImage {
        nsImage(named: "instagram", fallbackSVG: instagramSVG)
    }

    public static var appIconImage: NSImage? {
        let bundle = Bundle.main
        if let bundleURL = bundle.url(forResource: "AppIcon", withExtension: "icns") ??
                           bundle.url(forResource: "app-icon", withExtension: "png", subdirectory: "Icons") ??
                           bundle.url(forResource: "app-icon", withExtension: "png"),
           let img = NSImage(contentsOf: bundleURL) {
            return img
        }
        let devPaths = [
            "Resources/AppIcon.icns",
            "Resources/Icons/app-icon.png",
            "../Resources/AppIcon.icns",
            "../Resources/Icons/app-icon.png"
        ]
        for path in devPaths {
            if FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        if let appIcon = NSApplication.shared.applicationIconImage,
           appIcon.size.width > 0 && appIcon.size.height > 0 {
            return appIcon
        }
        return nil
    }
}

public struct AppIconView: View {
    public let size: CGFloat

    public init(size: CGFloat = 56) {
        self.size = size
    }

    public var body: some View {
        if let icon = BrandIcon.appIconImage {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .frame(width: size, height: size)
                Image(systemName: "play.tv")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundColor(Theme.accent)
            }
        }
    }
}
