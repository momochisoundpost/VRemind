import Foundation

public struct StreamStatus: Equatable, Sendable {
    public var isLive: Bool
    public var videoId: String?
    public var title: String?
    public var startedAt: Date?

    public init(isLive: Bool, videoId: String?, title: String?, startedAt: Date?) {
        self.isLive = isLive
        self.videoId = videoId
        self.title = title
        self.startedAt = startedAt
    }

    public static let offline = StreamStatus(isLive: false, videoId: nil, title: nil, startedAt: nil)

    /// The live video when we know its id, otherwise the channel's `/live` page.
    public func watchURL(channelHandle: String) -> URL {
        if isLive, let videoId, let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") {
            return url
        }
        return URL(string: "https://www.youtube.com/\(channelHandle)/live")!
    }
}
