import SwiftUI

public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bullet(text: String)
    case nestedBullet(indent: Int, text: String)
    case numberedList(index: Int, text: String)
    case taskItem(checked: Bool, text: String)
    case blockquote(text: String)
    case table(headers: [String], rows: [[String]])
    case codeBlock(code: String)
    case divider
    case image(url: URL, alt: String?)
    case video(url: URL, alt: String?)
}

public enum MarkdownParser: Sendable {
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    private static let linkedImageRegex = try! NSRegularExpression(
        pattern: #"^\[!\[([^\]]*)\]\((https?://[^\s\)]+)(?:\s+"[^"]*")?\)\]\((https?://[^\s\)]+)\)$"#
    )
    private static let markdownImageRegex = try! NSRegularExpression(
        pattern: #"^!\[([^\]]*)\]\((https?://[^\s\)]+)(?:\s+"[^"]*")?\)$"#
    )
    private static let markdownLinkRegex = try! NSRegularExpression(
        pattern: #"^\[([^\]]*)\]\((https?://[^\s\)]+)\)$"#
    )
    private static let htmlImgSrcRegex = try! NSRegularExpression(
        pattern: #"<img\b[^>]*\bsrc\s*=\s*["'](https?://[^"']+)["'][^>]*/?>"#,
        options: [.caseInsensitive]
    )
    private static let htmlImgAltRegex = try! NSRegularExpression(
        pattern: #"\balt\s*=\s*["']([^"']*)["']"#,
        options: [.caseInsensitive]
    )
    private static let htmlVideoSrcRegex = try! NSRegularExpression(
        pattern: #"<(?:video|source)\b[^>]*\bsrc\s*=\s*["'](https?://[^"']+)["']"#,
        options: [.caseInsensitive]
    )
    private static let tableSeparatorRegex = try! NSRegularExpression(
        pattern: #"^\|?[\s:\-]+\|[\s\|:\-]*$"#
    )
    private static let orderedListRegex = try! NSRegularExpression(
        pattern: #"^([0-9]+)\.\s+(.+)$"#
    )

    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var paragraphBuffer: [String] = []
        var blockquoteParagraphs: [String] = []
        var blockquoteCurrentLines: [String] = []
        var inCodeBlock = false
        var codeBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                blocks.append(.paragraph(text: joined))
            }
            paragraphBuffer.removeAll()
        }

        func flushBlockquote() {
            if !blockquoteCurrentLines.isEmpty {
                let joined = blockquoteCurrentLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty {
                    blockquoteParagraphs.append(joined)
                }
                blockquoteCurrentLines.removeAll()
            }
            guard !blockquoteParagraphs.isEmpty else { return }
            blocks.append(.blockquote(text: blockquoteParagraphs.joined(separator: "\n\n")))
            blockquoteParagraphs.removeAll()
        }

        var index = 0
        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushBlockquote()
                if inCodeBlock {
                    blocks.append(.codeBlock(code: codeBuffer.joined(separator: "\n")))
                    codeBuffer.removeAll()
                    inCodeBlock = false
                } else {
                    flushParagraph()
                    inCodeBlock = true
                }
                index += 1
                continue
            }

            if inCodeBlock {
                codeBuffer.append(rawLine)
                index += 1
                continue
            }

            if trimmed.lowercased().hasPrefix("<video") {
                flushParagraph()
                flushBlockquote()
                var videoLines = [trimmed]
                while !videoLines.last!.lowercased().contains("</video>"), index + 1 < lines.count {
                    index += 1
                    videoLines.append(lines[index].trimmingCharacters(in: .whitespaces))
                }
                let combined = videoLines.joined(separator: " ")
                if let videoBlock = parseVideoHTML(combined) {
                    blocks.append(videoBlock)
                } else {
                    paragraphBuffer.append(combined)
                }
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var after = trimmed.dropFirst()
                if after.first == " " {
                    after = after.dropFirst()
                }
                let content = String(after).trimmingCharacters(in: .whitespaces)
                if content.isEmpty {
                    if !blockquoteCurrentLines.isEmpty {
                        blockquoteParagraphs.append(blockquoteCurrentLines.joined(separator: " "))
                        blockquoteCurrentLines.removeAll()
                    }
                } else {
                    blockquoteCurrentLines.append(content)
                }
                index += 1
                continue
            } else {
                flushBlockquote()
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.divider)
                index += 1
                continue
            }

            if trimmed.contains("|"),
               index + 1 < lines.count,
               isTableSeparator(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
                flushParagraph()
                let headers = parseTableRow(trimmed)
                var rows: [[String]] = []
                index += 2
                while index < lines.count {
                    let rowLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard !rowLine.isEmpty, rowLine.contains("|") else { break }
                    var cells = parseTableRow(rowLine)
                    if cells.count < headers.count {
                        cells.append(contentsOf: Array(repeating: "", count: headers.count - cells.count))
                    } else if cells.count > headers.count {
                        cells = Array(cells.prefix(headers.count))
                    }
                    rows.append(cells)
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            if let videoBlock = parseMediaOrVideoLink(trimmed) {
                flushParagraph()
                blocks.append(videoBlock)
                index += 1
                continue
            }

            if let imageBlock = parseImage(trimmed) {
                flushParagraph()
                blocks.append(imageBlock)
                index += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                index += 1
                continue
            }

            if let taskBlock = parseTaskItem(trimmed) {
                flushParagraph()
                blocks.append(taskBlock)
                index += 1
                continue
            }

            if let bulletBlock = parseBullet(rawLine) {
                flushParagraph()
                blocks.append(bulletBlock)
                index += 1
                continue
            }

            if let numberedBlock = parseNumberedList(trimmed) {
                flushParagraph()
                blocks.append(numberedBlock)
                index += 1
                continue
            }

            paragraphBuffer.append(trimmed)
            index += 1
        }

        if inCodeBlock && !codeBuffer.isEmpty {
            blocks.append(.codeBlock(code: codeBuffer.joined(separator: "\n")))
        }
        flushBlockquote()
        flushParagraph()

        return blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        var level = 0
        for char in line {
            if char == "#" {
                level += 1
            } else {
                break
            }
        }
        guard level >= 1 && level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .heading(level: level, text: text)
    }

    private static func parseTaskItem(_ trimmed: String) -> MarkdownBlock? {
        let prefixes: [(String, Bool)] = [
            ("- [ ] ", false),
            ("* [ ] ", false),
            ("- [x] ", true),
            ("- [X] ", true),
            ("* [x] ", true),
            ("* [X] ", true)
        ]
        for (prefix, checked) in prefixes where trimmed.hasPrefix(prefix) {
            let text = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                return .taskItem(checked: checked, text: text)
            }
        }
        return nil
    }

    private static func parseBullet(_ rawLine: String) -> MarkdownBlock? {
        var leadingSpaces = 0
        for char in rawLine {
            if char == " " {
                leadingSpaces += 1
            } else if char == "\t" {
                leadingSpaces += 2
            } else {
                break
            }
        }
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") else {
            return nil
        }
        let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        let indent = leadingSpaces / 2
        if indent == 0 {
            return .bullet(text: content)
        }
        return .nestedBullet(indent: indent, text: content)
    }

    private static func parseNumberedList(_ trimmed: String) -> MarkdownBlock? {
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = orderedListRegex.firstMatch(in: trimmed, range: range),
              let numRange = Range(match.range(at: 1), in: trimmed),
              let textRange = Range(match.range(at: 2), in: trimmed),
              let index = Int(trimmed[numRange]) else {
            return nil
        }
        let text = String(trimmed[textRange]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .numberedList(index: index, text: text)
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..., in: line)
        return tableSeparatorRegex.firstMatch(in: line, range: range) != nil
    }

    private static func parseTableRow(_ line: String) -> [String] {
        var working = line.trimmingCharacters(in: .whitespaces)
        if working.hasPrefix("|") {
            working.removeFirst()
        }
        if working.hasSuffix("|") {
            working.removeLast()
        }
        return working
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseVideoHTML(_ html: String) -> MarkdownBlock? {
        let range = NSRange(html.startIndex..., in: html)
        guard let match = htmlVideoSrcRegex.firstMatch(in: html, range: range),
              let urlRange = Range(match.range(at: 1), in: html),
              let url = URL(string: String(html[urlRange])) else {
            return nil
        }
        return .video(url: url, alt: nil)
    }

    private static func parseMediaOrVideoLink(_ line: String) -> MarkdownBlock? {
        let range = NSRange(line.startIndex..., in: line)

        if let match = markdownImageRegex.firstMatch(in: line, range: range),
           let urlRange = Range(match.range(at: 2), in: line),
           let url = URL(string: String(line[urlRange])),
           videoExtensions.contains(url.pathExtension.lowercased()) {
            let alt = Range(match.range(at: 1), in: line).map { String(line[$0]) }
            return .video(url: url, alt: (alt?.isEmpty == true) ? nil : alt)
        }

        if let match = markdownLinkRegex.firstMatch(in: line, range: range),
           let urlRange = Range(match.range(at: 2), in: line),
           let url = URL(string: String(line[urlRange])),
           videoExtensions.contains(url.pathExtension.lowercased()) {
            let alt = Range(match.range(at: 1), in: line).map { String(line[$0]) }
            return .video(url: url, alt: (alt?.isEmpty == true) ? nil : alt)
        }

        return nil
    }

    private static func parseImage(_ line: String) -> MarkdownBlock? {
        let range = NSRange(line.startIndex..., in: line)

        if let match = linkedImageRegex.firstMatch(in: line, range: range),
           let urlRange = Range(match.range(at: 2), in: line),
           let url = URL(string: String(line[urlRange])) {
            let alt = Range(match.range(at: 1), in: line).map { String(line[$0]) }
            return .image(url: url, alt: (alt?.isEmpty == true) ? nil : alt)
        }

        if let match = markdownImageRegex.firstMatch(in: line, range: range),
           let urlRange = Range(match.range(at: 2), in: line),
           let url = URL(string: String(line[urlRange])) {
            let alt = Range(match.range(at: 1), in: line).map { String(line[$0]) }
            return .image(url: url, alt: (alt?.isEmpty == true) ? nil : alt)
        }

        if let match = htmlImgSrcRegex.firstMatch(in: line, range: range),
           let urlRange = Range(match.range(at: 1), in: line),
           let url = URL(string: String(line[urlRange])) {
            var alt: String? = nil
            if let altMatch = htmlImgAltRegex.firstMatch(in: line, range: range),
               let altRange = Range(altMatch.range(at: 1), in: line) {
                let rawAlt = String(line[altRange])
                if !rawAlt.isEmpty { alt = rawAlt }
            }
            return .image(url: url, alt: alt)
        }

        return nil
    }
}

public struct MarkdownView: View {
    public let blocks: [MarkdownBlock]

    private static let brRegex = try! NSRegularExpression(
        pattern: #"<br\s*/?>"#,
        options: [.caseInsensitive]
    )
    private static let bareURLRegex = try! NSRegularExpression(
        pattern: #"(?<![\(\[<])(https?://[^\s\)\]>]+)"#
    )

    public init(markdown: String) {
        self.blocks = MarkdownParser.parse(markdown)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(fontForHeading(level))
                .fontWeight(.bold)
                .padding(.top, level <= 2 ? 4 : 2)

        case .paragraph(let text):
            inlineText(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                    .font(.body)
                    .foregroundColor(.secondary)
                inlineText(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)

        case .nestedBullet(let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("◦")
                    .font(.body)
                    .foregroundColor(.secondary)
                inlineText(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(min(indent, 4)) * 16 + 4)

        case .numberedList(let index, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(index).")
                    .font(.body.monospacedDigit())
                    .foregroundColor(.secondary)
                inlineText(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)

        case .taskItem(let checked, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .foregroundColor(checked ? Theme.accent : .secondary)
                inlineText(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.accent)
                    .frame(width: 3)
                inlineText(text)
                    .font(.body)
                    .italic()
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(6)

        case .table(let headers, let rows):
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        inlineText(header)
                            .font(.callout.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))

                Divider()

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 8) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            inlineText(cell)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(rowIndex % 2 == 1 ? Color.secondary.opacity(0.04) : Color.clear)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .cornerRadius(6)

        case .codeBlock(let code):
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(6)

        case .divider:
            Divider()
                .padding(.vertical, 2)

        case .image(let url, let alt):
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 240)
                        .cornerRadius(6)
                case .failure:
                    Text(alt ?? url.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .empty:
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 40)
                @unknown default:
                    EmptyView()
                }
            }

        case .video(let url, let alt):
            MarkdownVideoPlayerView(url: url, alt: alt)
        }
    }

    private func fontForHeading(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }

    private func inlineText(_ raw: String) -> Text {
        let brNormalized = Self.brRegex.stringByReplacingMatches(
            in: raw,
            range: NSRange(raw.startIndex..., in: raw),
            withTemplate: "\n"
        )
        let autolinked = Self.bareURLRegex.stringByReplacingMatches(
            in: brNormalized,
            range: NSRange(brNormalized.startIndex..., in: brNormalized),
            withTemplate: "[$1]($1)"
        )
        if let attributed = try? AttributedString(
            markdown: autolinked,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attributed)
        }
        return Text(autolinked)
    }
}
