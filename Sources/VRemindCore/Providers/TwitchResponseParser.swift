import Foundation

public enum TwitchResponseParser {
    private struct UserPayload {
        let displayName: String?
        let avatarURL: URL?
        let stream: StreamPayload?
    }

    private struct StreamPayload {
        let id: String
        let title: String
        let createdAt: Date?
        let type: String
    }

    public static func parse(data: Data) -> LivePageResult {
        guard let user = extractUserPayload(from: data) else {
            return .unrecognized
        }

        guard let stream = user.stream else {
            return .notLive(channelTitle: user.displayName, avatarURL: user.avatarURL)
        }

        guard stream.type.lowercased() == "live", !stream.id.isEmpty else {
            return .notLive(channelTitle: user.displayName, avatarURL: user.avatarURL)
        }

        return .live(videoId: stream.id, title: stream.title, startedAt: stream.createdAt)
    }

    public static func extractChannelTitle(from data: Data) -> String? {
        guard let user = extractUserPayload(from: data) else {
            return nil
        }
        return user.displayName
    }

    public static func extractAvatarURL(from data: Data) -> URL? {
        guard let user = extractUserPayload(from: data) else {
            return nil
        }
        return user.avatarURL
    }

    private static func extractUserPayload(from data: Data) -> UserPayload? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
            return nil
        }

        guard let dataObj = json["data"] as? [String: Any],
              let userObj = dataObj["user"] as? [String: Any] else {
            return nil
        }

        let displayName = (userObj["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedDisplayName = (displayName?.isEmpty == false) ? displayName : nil

        let avatarURL = (userObj["profileImageURL"] as? String).flatMap { URL(string: $0) }

        var streamPayload: StreamPayload? = nil
        if let streamObj = userObj["stream"] as? [String: Any] {
            let id = (streamObj["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = (streamObj["title"] as? String) ?? ""
            let type = (streamObj["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let createdAt = (streamObj["createdAt"] as? String).flatMap { parseISO8601Date($0) }
            streamPayload = StreamPayload(id: id, title: title, createdAt: createdAt, type: type)
        }

        return UserPayload(
            displayName: cleanedDisplayName,
            avatarURL: avatarURL,
            stream: streamPayload
        )
    }

    private static func parseISO8601Date(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string)
    }
}
