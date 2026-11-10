import Foundation

public struct LoreEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var category: String
    public var summary: String
    public var tags: [String]

    public init(id: String, title: String, category: String, summary: String, tags: [String]) {
        self.id = id
        self.title = title
        self.category = category
        self.summary = summary
        self.tags = tags
    }
}
