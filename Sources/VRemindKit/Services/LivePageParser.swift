import Foundation

public enum LivePageResult: Equatable, Sendable {
    case live(videoId: String, title: String, startedAt: Date?)
    case upcoming(videoId: String, title: String, scheduledStartTime: Date?)
    case notLive(channelTitle: String?, avatarURL: URL?)
    case unrecognized
}

public enum LivePageParser {
    public static func parse(html: String) -> LivePageResult {
        if let jsonString = extractPlayerResponseJSON(from: html) {
            guard let data = jsonString.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return .unrecognized
            }
            let videoDetails = root["videoDetails"] as? [String: Any]
            let isLive = (videoDetails?["isLive"] as? Bool) == true
            let isUpcoming = (videoDetails?["isUpcoming"] as? Bool) == true

            let microformat = (root["microformat"] as? [String: Any])?["playerMicroformatRenderer"] as? [String: Any]
            let broadcastDetails = microformat?["liveBroadcastDetails"] as? [String: Any]
            let isLiveNow = (broadcastDetails?["isLiveNow"] as? Bool) == true

            let author = (videoDetails?["author"] as? String).flatMap { cleanTitle($0) }
            let channelTitle = author ?? extractChannelTitleFromTags(from: html)
            let avatarURL = extractAvatarURL(from: html)

            if (isLive || isLiveNow) && !isUpcoming {
                guard let videoId = videoDetails?["videoId"] as? String, !videoId.isEmpty else {
                    return .notLive(channelTitle: channelTitle, avatarURL: avatarURL)
                }
                let title = (videoDetails?["title"] as? String) ?? ""
                let startedAt: Date?
                if let startTimestamp = broadcastDetails?["startTimestamp"] as? String {
                    startedAt = parseISO8601Date(startTimestamp)
                } else {
                    startedAt = nil
                }
                return .live(videoId: videoId, title: title, startedAt: startedAt)
            }

            if isUpcoming {
                guard let videoId = videoDetails?["videoId"] as? String, !videoId.isEmpty else {
                    return .notLive(channelTitle: channelTitle, avatarURL: avatarURL)
                }
                let title = (videoDetails?["title"] as? String) ?? ""
                let scheduledStartTime: Date?
                if let startTimestamp = broadcastDetails?["startTimestamp"] as? String {
                    scheduledStartTime = parseISO8601Date(startTimestamp)
                } else {
                    scheduledStartTime = nil
                }
                return .upcoming(videoId: videoId, title: title, scheduledStartTime: scheduledStartTime)
            }

            return .notLive(channelTitle: channelTitle, avatarURL: avatarURL)
        }

        if html.contains("ytInitialData") {
            let channelTitle = extractChannelTitle(from: html)
            let avatarURL = extractAvatarURL(from: html)
            return .notLive(channelTitle: channelTitle, avatarURL: avatarURL)
        }
        return .unrecognized
    }

    public static func extractAvatarURL(from html: String) -> URL? {
        let prefix = "https://yt3.googleusercontent.com/"
        if let startRange = html.range(of: prefix) {
            let remainder = html[startRange.lowerBound...]
            let endIdx = remainder.firstIndex { char in
                char == "\"" || char == "'" || char == " " || char == ">" || char == "<" || char == "\\"
            } ?? remainder.endIndex
            let urlString = String(remainder[..<endIdx])
            return URL(string: urlString)
        }
        let escapedPrefix = "https:\\/\\/yt3.googleusercontent.com\\/"
        if let startRange = html.range(of: escapedPrefix) {
            let remainder = html[startRange.lowerBound...]
            let endIdx = remainder.firstIndex { char in
                char == "\"" || char == "'" || char == " " || char == ">" || char == "<"
            } ?? remainder.endIndex
            let unescaped = String(remainder[..<endIdx]).replacingOccurrences(of: "\\/", with: "/")
            return URL(string: unescaped)
        }
        return nil
    }

    public static func extractChannelTitle(from html: String) -> String? {
        if let jsonString = extractPlayerResponseJSON(from: html),
           let data = jsonString.data(using: .utf8),
           let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let videoDetails = root["videoDetails"] as? [String: Any],
           let author = videoDetails["author"] as? String,
           let cleaned = cleanTitle(author) {
            return cleaned
        }
        return extractChannelTitleFromTags(from: html)
    }

    private static func extractChannelTitleFromTags(from html: String) -> String? {
        let ogPatterns = [
            #"<meta\s+[^>]*property\s*=\s*["']og:title["'][^>]*content\s*=\s*["']([^"']+)["']"#,
            #"<meta\s+[^>]*content\s*=\s*["']([^"']+)["'][^>]*property\s*=\s*["']og:title["']"#
        ]
        for pattern in ogPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let candidate = cleanTitle(String(html[range]))
                if let candidate, !candidate.isEmpty {
                    return candidate
                }
            }
        }

        let titlePattern = #"<title>(.*?)</title>"#
        if let regex = try? NSRegularExpression(pattern: titlePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            let candidate = cleanTitle(String(html[range]))
            if let candidate, !candidate.isEmpty {
                return candidate
            }
        }

        return nil
    }

    private static func cleanTitle(_ raw: String) -> String? {
        var title = decodeHTMLEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if title.hasSuffix(" - YouTube") {
            title = String(title.dropLast(10)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if title.isEmpty || title == "YouTube" {
            return nil
        }
        return title
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func extractPlayerResponseJSON(from html: String) -> String? {
        let marker = "ytInitialPlayerResponse = {"
        guard let markerRange = html.range(of: marker) else {
            return nil
        }
        let openBraceIndex = html.index(before: markerRange.upperBound)
        var depth = 0
        var inString = false
        var isEscaped = false

        var index = openBraceIndex
        while index < html.endIndex {
            let char = html[index]
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if char == "\\" {
                    isEscaped = true
                } else if char == "\"" {
                    inString = false
                }
            } else {
                if char == "\"" {
                    inString = true
                } else if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        let end = html.index(after: index)
                        return String(html[openBraceIndex..<end])
                    }
                }
            }
            index = html.index(after: index)
        }
        return nil
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
