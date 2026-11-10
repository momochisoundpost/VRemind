import Foundation

public struct CuratedClip: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var youtubeUrl: String

    public init(id: String, title: String, youtubeUrl: String) {
        self.id = id
        self.title = title
        self.youtubeUrl = youtubeUrl
    }

    public var url: URL? {
        URL(string: youtubeUrl)
    }
}
