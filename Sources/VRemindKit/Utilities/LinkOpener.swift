import AppKit
import Foundation

public enum LinkOpener {
    public static func videoURL(for youtubeId: String) -> URL {
        URL(string: "https://www.youtube.com/watch?v=\(youtubeId)")!
    }

    public static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
