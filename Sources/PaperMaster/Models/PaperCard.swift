import Foundation
import SwiftData

@Model
final class PaperCard {
    @Attribute(.unique) var id: UUID
    var paper: Paper?
    var createdAt: Date
    var updatedAt: Date
    var formatVersion: Int
    var headline: String
    var venueLine: String
    var citationLine: String
    var keywordsPayload: String
    var sectionsPayload: String
    var htmlContent: String
    var htmlExportPath: String?

    init(
        id: UUID = UUID(),
        paper: Paper? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        formatVersion: Int = 1,
        headline: String,
        venueLine: String,
        citationLine: String,
        keywords: [String],
        sections: [PaperCardSection],
        htmlContent: String,
        htmlExportPath: String? = nil
    ) {
        self.id = id
        self.paper = paper
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.formatVersion = formatVersion
        self.headline = headline
        self.venueLine = venueLine
        self.citationLine = citationLine
        self.keywordsPayload = Self.encodeKeywords(keywords)
        self.sectionsPayload = Self.encodeSections(sections)
        self.htmlContent = htmlContent
        self.htmlExportPath = htmlExportPath
    }

    var keywords: [String] {
        get { Self.decodeKeywords(keywordsPayload) }
        set { keywordsPayload = Self.encodeKeywords(newValue) }
    }

    var sections: [PaperCardSection] {
        get { Self.decodeSections(sectionsPayload) }
        set { sectionsPayload = Self.encodeSections(newValue) }
    }

    var htmlExportURL: URL? {
        get {
            guard let htmlExportPath else { return nil }
            return URL(fileURLWithPath: htmlExportPath)
        }
        set {
            htmlExportPath = newValue?.path
        }
    }

    var plainTextExport: String {
        var lines: [String] = [headline]

        let trimmedVenue = venueLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedVenue.isEmpty == false {
            lines.append(trimmedVenue)
        }

        let trimmedCitation = citationLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCitation.isEmpty == false {
            lines.append(trimmedCitation)
        }

        if keywords.isEmpty == false {
            lines.append("Keywords: \(keywords.joined(separator: ", "))")
        }

        for section in sections {
            lines.append("")
            lines.append(section.title)
            lines.append(section.body)
        }

        return lines.joined(separator: "\n")
    }

    func update(
        headline: String,
        venueLine: String,
        citationLine: String,
        keywords: [String],
        sections: [PaperCardSection],
        htmlContent: String,
        updatedAt: Date = .now
    ) {
        self.headline = headline
        self.venueLine = venueLine
        self.citationLine = citationLine
        self.keywords = keywords
        self.sections = sections
        self.htmlContent = htmlContent
        self.updatedAt = updatedAt
    }

    private static func encodeKeywords(_ keywords: [String]) -> String {
        let payload = Array(Set(keywords.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { $0.isEmpty == false })).sorted()
        return encode(payload) ?? "[]"
    }

    private static func decodeKeywords(_ payload: String) -> [String] {
        decode([String].self, from: payload) ?? []
    }

    private static func encodeSections(_ sections: [PaperCardSection]) -> String {
        encode(sections) ?? "[]"
    }

    private static func decodeSections(_ payload: String) -> [PaperCardSection] {
        decode([PaperCardSection].self, from: payload) ?? []
    }

    private static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from payload: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(payload.utf8))
    }
}

struct PaperCardSection: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let emoji: String
    let body: String

    init(id: String, title: String, emoji: String, body: String) {
        self.id = id
        self.title = title
        self.emoji = emoji
        self.body = body
    }
}
