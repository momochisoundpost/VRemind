import Foundation

public enum LivePageResult: Equatable, Sendable {
    case live(videoId: String, title: String, startedAt: Date?)
    case notLive
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

            if (isLive || isLiveNow) && !isUpcoming {
                guard let videoId = videoDetails?["videoId"] as? String, !videoId.isEmpty else {
                    return .notLive
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
            return .notLive
        }

        if html.contains("ytInitialData") {
            return .notLive
        }
        return .unrecognized
    }

    public static func extractAvatarURL(from html: String) -> URL? {
        let prefix = "https://yt3.googleusercontent.com/"
        guard let startRange = html.range(of: prefix) else {
            return nil
        }
        let remainder = html[startRange.lowerBound...]
        let endIdx = remainder.firstIndex { char in
            char == "\"" || char == "'" || char == " " || char == ">" || char == "<" || char == "\\"
        } ?? remainder.endIndex
        let urlString = String(remainder[..<endIdx])
        return URL(string: urlString)
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
