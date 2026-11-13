import Foundation

public enum CelebrationType: Equatable, Sendable {
    case birthday
    case debut
    case anniversary
    case developerBirthday
}

public struct CelebrationResult: Equatable, Sendable {
    public let isCelebration: Bool
    public let type: CelebrationType?
    public let matchedKeyword: String?

    public static let none = CelebrationResult(isCelebration: false, type: nil, matchedKeyword: nil)

    public init(isCelebration: Bool, type: CelebrationType? = nil, matchedKeyword: String? = nil) {
        self.isCelebration = isCelebration
        self.type = type
        self.matchedKeyword = matchedKeyword
    }
}

public enum CelebrationDetector: Sendable {
    private struct KeywordRule: @unchecked Sendable {
        let keyword: String
        let regex: NSRegularExpression?
        let isCJK: Bool

        init(wordBoundary keyword: String) {
            self.keyword = keyword
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            self.regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            self.isCJK = false
        }

        init(cjkSubstring keyword: String) {
            self.keyword = keyword
            self.regex = nil
            self.isCJK = true
        }

        func matches(in text: String) -> Bool {
            if isCJK {
                return text.range(of: keyword, options: .caseInsensitive) != nil
            }
            guard let regex else { return false }
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }

    private struct PriorityGroup: @unchecked Sendable {
        let type: CelebrationType
        let rules: [KeywordRule]
    }

    private static let priorityGroups: [PriorityGroup] = [
        // 1. Birthday
        PriorityGroup(
            type: .birthday,
            rules: [
                // English
                KeywordRule(wordBoundary: "birthday stream"),
                KeywordRule(wordBoundary: "birthday"),
                KeywordRule(wordBoundary: "bday"),
                // Indonesian
                KeywordRule(wordBoundary: "ultah"),
                KeywordRule(wordBoundary: "ulang tahun"),
                // Japanese (CJK)
                KeywordRule(cjkSubstring: "生誕祭"),
                KeywordRule(cjkSubstring: "誕生日"),
                KeywordRule(cjkSubstring: "バースデー")
            ]
        ),
        // 2. Debut
        PriorityGroup(
            type: .debut,
            rules: [
                // English
                KeywordRule(wordBoundary: "re-debut"),
                KeywordRule(wordBoundary: "redebut"),
                KeywordRule(wordBoundary: "debut"),
                // Japanese (CJK)
                KeywordRule(cjkSubstring: "初配信"),
                KeywordRule(cjkSubstring: "お披露目")
            ]
        ),
        // 3. Anniversary
        PriorityGroup(
            type: .anniversary,
            rules: [
                // English
                KeywordRule(wordBoundary: "anniversary"),
                KeywordRule(wordBoundary: "anni"),
                // Indonesian
                KeywordRule(wordBoundary: "hari jadi"),
                KeywordRule(wordBoundary: "anniv"),
                // Japanese (CJK)
                KeywordRule(cjkSubstring: "周年"),
                KeywordRule(cjkSubstring: "記念配信"),
                KeywordRule(cjkSubstring: "記念枠")
            ]
        )
    ]

    public static func detect(title: String) -> CelebrationResult {
        guard !title.isEmpty else { return .none }

        for group in priorityGroups {
            for rule in group.rules {
                if rule.matches(in: title) {
                    return CelebrationResult(isCelebration: true, type: group.type, matchedKeyword: rule.keyword)
                }
            }
        }

        return .none
    }

    public static func isTargetDeveloperChannel(_ channel: WatchedChannel) -> Bool {
        let cleanHandle = channel.handle.trimmingCharacters(in: CharacterSet(charactersIn: "@ \t\n\r")).lowercased()
        if cleanHandle == "bukancaitlyn" {
            return true
        }

        var idString = channel.id
        if idString.hasPrefix("youtube:") {
            idString = String(idString.dropFirst("youtube:".count))
        }
        let cleanId = idString.trimmingCharacters(in: CharacterSet(charactersIn: "@ \t\n\r")).lowercased()
        if cleanId == "bukancaitlyn" {
            return true
        }

        let cleanName = channel.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleanName == "caitlyn momochi" {
            return true
        }

        return false
    }

    public static func isDeveloperBirthday(date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return false
        }
        return month == 12 && day == 31 && year > 1999
    }

    public static func detect(
        status: StreamStatus,
        channel: WatchedChannel,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> CelebrationResult {
        switch status {
        case .live(_, let title, _), .upcoming(_, let title, _):
            let titleResult = detect(title: title)
            if titleResult.isCelebration {
                return titleResult
            }
        case .offline, .unknown:
            break
        }

        if isTargetDeveloperChannel(channel) && isDeveloperBirthday(date: date, calendar: calendar) {
            return CelebrationResult(isCelebration: true, type: .developerBirthday, matchedKeyword: nil)
        }

        return .none
    }

    public static func shouldShowConfetti(
        channels: [WatchedChannel],
        statuses: [String: StreamStatus],
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        if isDeveloperBirthday(date: date, calendar: calendar) {
            if channels.contains(where: { isTargetDeveloperChannel($0) }) {
                return true
            }
        }

        let relevantStatuses: [StreamStatus] = channels.isEmpty
            ? Array(statuses.values)
            : channels.compactMap { statuses[$0.id] }

        for status in relevantStatuses {
            switch status {
            case .live(_, let title, _):
                if detect(title: title).isCelebration {
                    return true
                }
            case .upcoming(_, let title, let scheduledStartTime):
                if detect(title: title).isCelebration {
                    if let scheduledStartTime, calendar.isDate(scheduledStartTime, inSameDayAs: date) {
                        return true
                    }
                }
            case .offline, .unknown:
                break
            }
        }

        return false
    }
}
