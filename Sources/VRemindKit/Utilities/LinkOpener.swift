import AppKit
import Foundation

public enum LinkOpener {
    private static let fallbackURL = URL(string: "https://www.youtube.com")!

    public static func videoURL(for youtubeId: String) -> URL {
        let encoded = youtubeId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? youtubeId
        return URL(string: "https://www.youtube.com/watch?v=\(encoded)") ?? fallbackURL
    }

    public static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
