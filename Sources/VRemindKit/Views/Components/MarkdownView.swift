import SwiftUI

public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bullet(text: String)
    case codeBlock(code: String)
    case divider
    case image(url: URL, alt: String?)
}

public enum MarkdownParser: Sendable {
    private static let markdownImageRegex = try! NSRegularExpression(
        pattern: #"^!\[([^\]]*)\]\((https?://[^\s\)]+)\)$"#
    )
    private static let htmlImgSrcRegex = try! NSRegularExpression(
        pattern: #"<img\b[^>]*\bsrc\s*=\s*["'](https?://[^"']+)["'][^>]*/?>"#,
        options: [.caseInsensitive]
    )
    private static let htmlImgAltRegex = try! NSRegularExpression(
        pattern: #"\balt\s*=\s*["']([^"']*)["']"#,
        options: [.caseInsensitive]
    )

    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var paragraphBuffer: [String] = []
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

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.codeBlock(code: codeBuffer.joined(separator: "\n")))
                    codeBuffer.removeAll()
                    inCodeBlock = false
                } else {
                    flushParagraph()
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeBuffer.append(rawLine)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.divider)
                continue
            }

            if let imageBlock = parseImage(trimmed) {
                flushParagraph()
                blocks.append(imageBlock)
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty {
                    blocks.append(.bullet(text: content))
                }
                continue
            }

            paragraphBuffer.append(trimmed)
        }

        if inCodeBlock && !codeBuffer.isEmpty {
            blocks.append(.codeBlock(code: codeBuffer.joined(separator: "\n")))
        }
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

    private static func parseImage(_ line: String) -> MarkdownBlock? {
        let range = NSRange(line.startIndex..., in: line)

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
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attributed)
        }
        return Text(raw)
    }
}
