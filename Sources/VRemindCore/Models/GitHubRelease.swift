import Foundation

public struct GitHubReleaseAsset: Codable, Equatable, Sendable {
    public let name: String
    public let browserDownloadURL: URL
    public let size: Int?

    public init(
        name: String,
        browserDownloadURL: URL,
        size: Int? = nil
    ) {
        self.name = name
        self.browserDownloadURL = browserDownloadURL
        self.size = size
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        self.name = try container.decode(String.self, forKey: DynamicKey(stringValue: "name")!)
        self.size = try container.decodeIfPresent(Int.self, forKey: DynamicKey(stringValue: "size")!)

        let urlCandidates = ["browserDownloadURL", "browserDownloadUrl", "browser_download_url"]
        var decodedURL: URL?
        for candidate in urlCandidates {
            if let key = DynamicKey(stringValue: candidate),
               let url = try? container.decodeIfPresent(URL.self, forKey: key) {
                decodedURL = url
                break
            }
        }
        guard let finalURL = decodedURL else {
            throw DecodingError.keyNotFound(
                DynamicKey(stringValue: "browser_download_url")!,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "No browser download URL found")
            )
        }
        self.browserDownloadURL = finalURL
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(browserDownloadURL, forKey: .browserDownloadURL)
        try container.encodeIfPresent(size, forKey: .size)
    }
}

public struct GitHubRelease: Codable, Equatable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: URL
    public let publishedAt: Date?
    public let assets: [GitHubReleaseAsset]

    public init(
        tagName: String,
        name: String? = nil,
        body: String? = nil,
        htmlURL: URL,
        publishedAt: Date? = nil,
        assets: [GitHubReleaseAsset] = []
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
        self.assets = assets
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)

        let tagCandidates = ["tagName", "tag_name"]
        var decodedTag: String?
        for candidate in tagCandidates {
            if let key = DynamicKey(stringValue: candidate),
               let tag = try? container.decodeIfPresent(String.self, forKey: key) {
                decodedTag = tag
                break
            }
        }
        guard let finalTag = decodedTag else {
            throw DecodingError.keyNotFound(
                DynamicKey(stringValue: "tag_name")!,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "tag_name not found")
            )
        }
        self.tagName = finalTag

        self.name = try? container.decodeIfPresent(String.self, forKey: DynamicKey(stringValue: "name")!)
        self.body = try? container.decodeIfPresent(String.self, forKey: DynamicKey(stringValue: "body")!)

        let urlCandidates = ["htmlURL", "htmlUrl", "html_url"]
        var decodedURL: URL?
        for candidate in urlCandidates {
            if let key = DynamicKey(stringValue: candidate),
               let url = try? container.decodeIfPresent(URL.self, forKey: key) {
                decodedURL = url
                break
            }
        }
        guard let finalURL = decodedURL else {
            throw DecodingError.keyNotFound(
                DynamicKey(stringValue: "html_url")!,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "html_url not found")
            )
        }
        self.htmlURL = finalURL

        let dateCandidates = ["publishedAt", "published_at"]
        var decodedDate: Date?
        for candidate in dateCandidates {
            if let key = DynamicKey(stringValue: candidate) {
                if let d = try? container.decodeIfPresent(Date.self, forKey: key) {
                    decodedDate = d
                    break
                }
                if let s = try? container.decodeIfPresent(String.self, forKey: key),
                   let d = ISO8601DateFormatter().date(from: s) {
                    decodedDate = d
                    break
                }
            }
        }
        self.publishedAt = decodedDate

        let assetsCandidates = ["assets"]
        var decodedAssets: [GitHubReleaseAsset] = []
        for candidate in assetsCandidates {
            if let key = DynamicKey(stringValue: candidate),
               let items = try? container.decodeIfPresent([GitHubReleaseAsset].self, forKey: key) {
                decodedAssets = items
                break
            }
        }
        self.assets = decodedAssets
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tagName, forKey: .tagName)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encode(htmlURL, forKey: .htmlURL)
        try container.encodeIfPresent(publishedAt, forKey: .publishedAt)
        try container.encode(assets, forKey: .assets)
    }
}
