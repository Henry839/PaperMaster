import AppKit
import Foundation
import SwiftData

enum ReaderHighlightColor: String, CaseIterable, Codable, Identifiable {
    case yellow
    case mint
    case pink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yellow:
            return "Yellow"
        case .mint:
            return "Mint"
        case .pink:
            return "Pink"
        }
    }

    var pdfColor: NSColor {
        switch self {
        case .yellow:
            return NSColor.systemYellow.withAlphaComponent(0.34)
        case .mint:
            return NSColor.systemMint.withAlphaComponent(0.30)
        case .pink:
            return NSColor.systemPink.withAlphaComponent(0.28)
        }
    }
}

struct ReaderAnnotationRect: Codable, Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(rect: CGRect) {
        self.x = Self.rounded(rect.origin.x)
        self.y = Self.rounded(rect.origin.y)
        self.width = Self.rounded(rect.size.width)
        self.height = Self.rounded(rect.size.height)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    private static func rounded(_ value: CGFloat) -> Double {
        let precision = 1_000.0
        return (Double(value) * precision).rounded() / precision
    }
}

enum ReaderRectPayloadCodec {
    static func encode(_ rects: [ReaderAnnotationRect]) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(rects),
              let payload = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return payload
    }

    static func encode(_ rects: [CGRect]) -> String {
        encode(rects.map(ReaderAnnotationRect.init(rect:)))
    }

    static func decode(_ payload: String) -> [ReaderAnnotationRect] {
        guard let data = payload.data(using: .utf8),
              let rects = try? JSONDecoder().decode([ReaderAnnotationRect].self, from: data) else {
            return []
        }
        return rects
    }
}

struct ReaderHighlightOverlayIdentity: Equatable {
    static let prefix = "henrypaper"

    let annotationID: UUID
    let rectIndex: Int

    init(annotationID: UUID, rectIndex: Int) {
        self.annotationID = annotationID
        self.rectIndex = rectIndex
    }

    init?(userName: String?) {
        guard let userName else { return nil }

        let components = userName.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 3,
              String(components[0]) == Self.prefix,
              let annotationID = UUID(uuidString: String(components[1])),
              let rectIndex = Int(components[2]),
              rectIndex >= 0 else {
            return nil
        }

        self.annotationID = annotationID
        self.rectIndex = rectIndex
    }

    var userName: String {
        "\(Self.prefix):\(annotationID.uuidString):\(rectIndex)"
    }
}

struct ReaderSelectionSnapshot: Equatable {
    let pageIndex: Int
    let quotedText: String
    let rects: [ReaderAnnotationRect]

    init?(pageIndex: Int, quotedText: String, rects: [CGRect]) {
        let normalizedText = quotedText.normalizedReaderContent
        let normalizedRects = rects
            .filter { $0.isNull == false && $0.isInfinite == false }
            .map(ReaderAnnotationRect.init(rect:))
            .filter { $0.width > 0.01 && $0.height > 0.01 }

        guard pageIndex >= 0,
              normalizedText.isEmpty == false,
              normalizedRects.isEmpty == false else {
            return nil
        }

        self.pageIndex = pageIndex
        self.quotedText = normalizedText
        self.rects = normalizedRects
    }

    var rectPayload: String {
        ReaderRectPayloadCodec.encode(rects)
    }
}

@Model
final class PaperAnnotation {
    @Attribute(.unique) var id: UUID
    var pageIndex: Int
    var quotedText: String
    var noteText: String
    var colorRawValue: String
    var rectPayload: String
    var createdAt: Date
    var updatedAt: Date
    var paper: Paper

    init(
        id: UUID = UUID(),
        paper: Paper,
        pageIndex: Int,
        quotedText: String,
        noteText: String = "",
        color: ReaderHighlightColor = .yellow,
        rectPayload: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.paper = paper
        self.pageIndex = pageIndex
        self.quotedText = quotedText.normalizedReaderContent
        self.noteText = noteText
        self.colorRawValue = color.rawValue
        self.rectPayload = rectPayload
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension PaperAnnotation {
    var color: ReaderHighlightColor {
        get { ReaderHighlightColor(rawValue: colorRawValue) ?? .yellow }
        set { colorRawValue = newValue.rawValue }
    }

    var rects: [ReaderAnnotationRect] {
        get { ReaderRectPayloadCodec.decode(rectPayload) }
        set { rectPayload = ReaderRectPayloadCodec.encode(newValue) }
    }

    var pageNumber: Int {
        pageIndex + 1
    }

    var hasNote: Bool {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var notePreviewText: String {
        let trimmed = noteText.normalizedReaderContent
        return trimmed.isEmpty ? "No note yet." : trimmed
    }

    func matches(_ selection: ReaderSelectionSnapshot) -> Bool {
        pageIndex == selection.pageIndex
            && quotedText.normalizedReaderContent == selection.quotedText.normalizedReaderContent
            && rects == selection.rects
    }

    func touch() {
        updatedAt = .now
    }

    func overlayIdentity(forRectAt rectIndex: Int) -> ReaderHighlightOverlayIdentity {
        ReaderHighlightOverlayIdentity(annotationID: id, rectIndex: rectIndex)
    }

    static func sidebarSort(lhs: PaperAnnotation, rhs: PaperAnnotation) -> Bool {
        if lhs.pageIndex != rhs.pageIndex {
            return lhs.pageIndex < rhs.pageIndex
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
