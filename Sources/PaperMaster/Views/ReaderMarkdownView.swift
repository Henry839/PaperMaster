import SwiftUI

struct ReaderMarkdownView: View {
    private let document: ReaderMarkdownDocument

    init(markdown: String) {
        document = ReaderMarkdownDocument(markdown: markdown)
    }

    var body: some View {
        ReaderMarkdownBlocksView(blocks: document.blocks)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReaderMarkdownDocument: Equatable {
    let blocks: [ReaderMarkdownBlock]

    init(markdown: String) {
        blocks = ReaderMarkdownDocument.parse(markdown)
    }

    private static func parse(_ markdown: String) -> [ReaderMarkdownBlock] {
        let lines = markdown.normalizedMarkdownLineEndings
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var blocks: [ReaderMarkdownBlock] = []
        var paragraphLines: [String] = []
        var index = 0

        func flushParagraph() {
            let paragraph = paragraphLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard paragraph.isEmpty == false else {
                paragraphLines.removeAll(keepingCapacity: true)
                return
            }

            blocks.append(.paragraph(paragraph))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let fence = codeFence(in: trimmed) {
                flushParagraph()
                index += 1

                var codeLines: [String] = []
                while index < lines.count {
                    let currentLine = lines[index]
                    if currentLine.trimmingCharacters(in: .whitespaces).hasPrefix(fence.marker) {
                        index += 1
                        break
                    }

                    codeLines.append(currentLine)
                    index += 1
                }

                let code = codeLines
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .newlines)
                blocks.append(.codeBlock(language: fence.language, code: code))
                continue
            }

            if let heading = heading(in: trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()

                var quoteLines: [String] = []
                while index < lines.count {
                    let currentLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard currentLine.hasPrefix(">") else {
                        break
                    }

                    var quoteLine = String(currentLine.dropFirst())
                    if quoteLine.hasPrefix(" ") {
                        quoteLine.removeFirst()
                    }

                    quoteLines.append(quoteLine)
                    index += 1
                }

                let quote = quoteLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
                if quote.isEmpty == false {
                    blocks.append(.blockquote(quote))
                }
                continue
            }

            if let item = unorderedListItem(in: line) {
                flushParagraph()

                var items = [item]
                index += 1

                while index < lines.count {
                    let currentLine = lines[index]
                    let currentTrimmed = currentLine.trimmingCharacters(in: .whitespaces)

                    if currentTrimmed.isEmpty {
                        index += 1
                        break
                    }

                    if let nextItem = unorderedListItem(in: currentLine) {
                        items.append(nextItem)
                        index += 1
                        continue
                    }

                    if let continuation = listContinuation(in: currentLine) {
                        items[items.index(before: items.endIndex)].append("\n\(continuation)")
                        index += 1
                        continue
                    }

                    break
                }

                blocks.append(.unorderedList(items))
                continue
            }

            if let item = orderedListItem(in: line) {
                flushParagraph()

                let startIndex = item.number
                var items = [item.content]
                index += 1

                while index < lines.count {
                    let currentLine = lines[index]
                    let currentTrimmed = currentLine.trimmingCharacters(in: .whitespaces)

                    if currentTrimmed.isEmpty {
                        index += 1
                        break
                    }

                    if let nextItem = orderedListItem(in: currentLine) {
                        items.append(nextItem.content)
                        index += 1
                        continue
                    }

                    if let continuation = listContinuation(in: currentLine) {
                        items[items.index(before: items.endIndex)].append("\n\(continuation)")
                        index += 1
                        continue
                    }

                    break
                }

                blocks.append(.orderedList(startingAt: startIndex, items: items))
                continue
            }

            paragraphLines.append(trimmed)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        guard let markerRange = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) else {
            return nil
        }

        let level = line.prefix { $0 == "#" }.count
        let text = String(line[markerRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }

    private static func unorderedListItem(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            let content = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            return content.isEmpty ? nil : content
        }

        return nil
    }

    private static func orderedListItem(in line: String) -> (number: Int, content: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let markerRange = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) else {
            return nil
        }

        let marker = trimmed[..<markerRange.upperBound]
        let digits = marker.prefix { $0.isNumber }
        guard let number = Int(digits) else {
            return nil
        }

        let content = String(trimmed[markerRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        return content.isEmpty ? nil : (number, content)
    }

    private static func listContinuation(in line: String) -> String? {
        guard line.first?.isWhitespace == true else {
            return nil
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty == false else {
            return nil
        }

        guard heading(in: trimmed) == nil,
              codeFence(in: trimmed) == nil,
              unorderedListItem(in: line) == nil,
              orderedListItem(in: line) == nil,
              trimmed.hasPrefix(">") == false else {
            return nil
        }

        return trimmed
    }

    private static func codeFence(in line: String) -> (marker: String, language: String?)? {
        let backticks = line.prefix { $0 == "`" }
        guard backticks.count >= 3 else {
            return nil
        }

        let marker = String(backticks)
        let language = line
            .dropFirst(backticks.count)
            .trimmingCharacters(in: .whitespaces)

        return (marker, language.isEmpty ? nil : String(language))
    }
}

enum ReaderMarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList(startingAt: Int, items: [String])
    case blockquote(String)
    case codeBlock(language: String?, code: String)

    var plainText: String {
        switch self {
        case let .heading(_, text), let .paragraph(text):
            return ReaderMarkdownRenderer.plainText(from: text)
        case let .unorderedList(items):
            return items
                .map(ReaderMarkdownRenderer.plainText(from:))
                .joined(separator: "\n")
        case let .orderedList(startingAt, items):
            return items.enumerated()
                .map { offset, item in
                    "\(startingAt + offset). \(ReaderMarkdownRenderer.plainText(from: item))"
                }
                .joined(separator: "\n")
        case let .blockquote(markdown):
            return ReaderMarkdownDocument(markdown: markdown).blocks
                .map(\.plainText)
                .joined(separator: "\n")
        case let .codeBlock(_, code):
            return code
        }
    }
}

enum ReaderMarkdownRenderer {
    private static let inlineOptions: AttributedString.MarkdownParsingOptions = {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        return options
    }()

    static func attributedText(from markdown: String) -> AttributedString {
        guard markdown.isEmpty == false else {
            return AttributedString("")
        }

        if let rendered = try? AttributedString(markdown: markdown, options: inlineOptions) {
            return rendered
        }

        return AttributedString(markdown)
    }

    static func plainText(from markdown: String) -> String {
        String(attributedText(from: markdown).characters)
    }
}

private struct ReaderMarkdownBlocksView: View {
    let blocks: [ReaderMarkdownBlock]
    var nested = false

    var body: some View {
        VStack(alignment: .leading, spacing: nested ? 10 : 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                ReaderMarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReaderMarkdownBlockView: View {
    let block: ReaderMarkdownBlock

    var body: some View {
        switch block {
        case let .heading(level, text):
            Text(ReaderMarkdownRenderer.attributedText(from: text))
                .font(headingFont(for: level))
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

        case let .paragraph(text):
            inlineText(text)

        case let .unorderedList(items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(marker: "\u{2022}", markdown: item)
                }
            }

        case let .orderedList(startIndex, items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                    listRow(marker: "\(startIndex + offset).", markdown: item)
                }
            }

        case let .blockquote(markdown):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)

                ReaderMarkdownBlocksView(
                    blocks: ReaderMarkdownDocument(markdown: markdown).blocks,
                    nested: true
                )
            }
            .padding(12)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        case let .codeBlock(_, code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: code)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func inlineText(_ markdown: String) -> some View {
        Text(ReaderMarkdownRenderer.attributedText(from: markdown))
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func listRow(marker: String, markdown: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(marker)
                .font(.body.weight(.semibold))
                .frame(width: 22, alignment: .leading)

            inlineText(markdown)
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .title3
        case 2:
            return .headline
        default:
            return .subheadline
        }
    }
}

private extension String {
    var normalizedMarkdownLineEndings: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
