import Foundation

public struct ReplayVOD: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var youtubeId: String
    public var date: Date
    public var duration: String

    public init(id: String, title: String, youtubeId: String, date: Date, duration: String) {
        self.id = id
        self.title = title
        self.youtubeId = youtubeId
        self.date = date
        self.duration = duration
    }

    public var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(youtubeId)")!
    }

    public var thumbnailURL: URL {
        URL(string: "https://i.ytimg.com/vi/\(youtubeId)/mqdefault.jpg")!
    }
}
