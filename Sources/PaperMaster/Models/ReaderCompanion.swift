import AppKit
import Foundation
import PDFKit

enum ReaderFocusPassageSource: String, Equatable, Sendable {
    case selection
    case viewport
}

struct ReaderPassageJumpTarget: Equatable, Sendable {
    let pageIndex: Int
    let rects: [ReaderAnnotationRect]

    var focusPoint: CGPoint {
        rects.first.map { CGPoint(x: $0.x, y: $0.y + $0.height) } ?? .zero
    }
}

struct ReaderFocusPassageSnapshot: Equatable, Sendable {
    let pageIndex: Int
    let quotedText: String
    let rects: [ReaderAnnotationRect]
    let source: ReaderFocusPassageSource

    init?(
        pageIndex: Int,
        quotedText: String,
        rects: [ReaderAnnotationRect],
        source: ReaderFocusPassageSource
    ) {
        let normalizedText = quotedText.normalizedReaderContent
        let normalizedRects = rects.filter { $0.width > 0.01 && $0.height > 0.01 }

        guard pageIndex >= 0,
              normalizedText.isEmpty == false,
              normalizedRects.isEmpty == false else {
            return nil
        }

        self.pageIndex = pageIndex
        self.quotedText = normalizedText
        self.rects = normalizedRects
        self.source = source
    }

    init?(selection: ReaderSelectionSnapshot) {
        self.init(
            pageIndex: selection.pageIndex,
            quotedText: selection.quotedText,
            rects: selection.rects,
            source: .selection
        )
    }

    var pageNumber: Int {
        pageIndex + 1
    }

    var normalizedKey: String {
        "\(pageIndex):\(quotedText.normalizedReaderContent.lowercased())"
    }

    var jumpTarget: ReaderPassageJumpTarget {
        ReaderPassageJumpTarget(pageIndex: pageIndex, rects: rects)
    }

    var anchorRect: ReaderAnnotationRect? {
        rects.first
    }
}

enum ReaderElfMood: String, CaseIterable, Equatable, Sendable {
    case skeptical
    case alarmed
    case amused
    case intrigued

    var displayName: String {
        switch self {
        case .skeptical:
            return "Skeptical"
        case .alarmed:
            return "Alarmed"
        case .amused:
            return "Amused"
        case .intrigued:
            return "Intrigued"
        }
    }

    var symbolName: String {
        switch self {
        case .skeptical:
            return "eye.trianglebadge.exclamationmark"
        case .alarmed:
            return "bolt.badge.clock"
        case .amused:
            return "face.smiling"
        case .intrigued:
            return "sparkles"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .skeptical:
            return NSColor.systemOrange
        case .alarmed:
            return NSColor.systemRed
        case .amused:
            return NSColor.systemTeal
        case .intrigued:
            return NSColor.systemMint
        }
    }

    var bubbleTint: NSColor {
        accentColor.withAlphaComponent(0.14)
    }
}

struct ReaderElfComment: Identifiable, Equatable, Sendable {
    let id: UUID
    let passage: ReaderFocusPassageSnapshot
    let mood: ReaderElfMood
    let text: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        passage: ReaderFocusPassageSnapshot,
        mood: ReaderElfMood,
        text: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.passage = passage
        self.mood = mood
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
    }
}

struct ReaderElfPauseReason: Equatable, Sendable {
    let message: String

    init(_ message: String) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        self.message = trimmedMessage.isEmpty ? "The elf is paused." : trimmedMessage
    }
}

enum ReaderElfStatus: Equatable {
    case off
    case listening
    case thinking
    case coolingDown(until: Date)
    case paused(ReaderElfPauseReason)

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .listening:
            return "Listening"
        case .thinking:
            return "Thinking"
        case .coolingDown:
            return "Cooling down"
        case .paused:
            return "Paused"
        }
    }

    var symbolName: String {
        switch self {
        case .off:
            return "moon.zzz"
        case .listening:
            return "ear.badge.waveform"
        case .thinking:
            return "ellipsis.bubble"
        case .coolingDown:
            return "timer"
        case .paused:
            return "pause.circle"
        }
    }
}

struct ReaderElfSessionState: Equatable {
    static let maximumRecentComments = 5
    static let maximumPromptComments = 3

    var enabled = true
    var activeComment: ReaderElfComment?
    var recentComments: [ReaderElfComment] = []
    var cooldownUntil: Date?
    var pausedReason: ReaderElfPauseReason?
    var isThinking = false
    var lastCompletedPassageKey: String?

    var promptContextComments: [ReaderElfComment] {
        Array(recentComments.prefix(Self.maximumPromptComments))
    }

    func status(now: Date = .now) -> ReaderElfStatus {
        guard enabled else { return .off }
        if let pausedReason {
            return .paused(pausedReason)
        }
        if isThinking {
            return .thinking
        }
        if let cooldownUntil, cooldownUntil > now {
            return .coolingDown(until: cooldownUntil)
        }
        return .listening
    }

    func canEvaluate(_ passage: ReaderFocusPassageSnapshot, now: Date = .now) -> Bool {
        guard enabled,
              pausedReason == nil,
              isThinking == false else {
            return false
        }

        if let cooldownUntil, cooldownUntil > now {
            return false
        }

        return lastCompletedPassageKey != passage.normalizedKey
    }

    mutating func setEnabled(_ isEnabled: Bool) {
        enabled = isEnabled
        isThinking = false
        pausedReason = nil
        activeComment = isEnabled ? activeComment : nil
    }

    mutating func beginEvaluation() {
        guard enabled else { return }
        isThinking = true
        pausedReason = nil
    }

    mutating func cancelEvaluation() {
        isThinking = false
    }

    mutating func finishWithoutComment(for passage: ReaderFocusPassageSnapshot) {
        isThinking = false
        pausedReason = nil
        lastCompletedPassageKey = passage.normalizedKey
    }

    mutating func surface(_ comment: ReaderElfComment, cooldown: TimeInterval = 45) {
        isThinking = false
        pausedReason = nil
        activeComment = comment
        lastCompletedPassageKey = comment.passage.normalizedKey
        recentComments.insert(comment, at: 0)
        if recentComments.count > Self.maximumRecentComments {
            recentComments = Array(recentComments.prefix(Self.maximumRecentComments))
        }
        cooldownUntil = comment.createdAt.addingTimeInterval(cooldown)
    }

    mutating func dismissActiveComment() {
        activeComment = nil
    }

    mutating func pause(_ reason: ReaderElfPauseReason) {
        isThinking = false
        pausedReason = reason
    }

    mutating func clearPause() {
        pausedReason = nil
    }

    mutating func reset() {
        self = ReaderElfSessionState()
    }
}

enum ReaderElfDockCorner: Equatable {
    case bottomRight
}

enum ReaderElfBubblePlacement: String, Equatable {
    case above
    case below
    case leading
    case trailing
}

struct ReaderElfGeometrySnapshot: Equatable {
    let paneBounds: CGRect
    let pageFrame: CGRect?
    let anchorFrame: CGRect?

    @MainActor
    static func capture(for passage: ReaderFocusPassageSnapshot?, in pdfView: PDFView) -> ReaderElfGeometrySnapshot {
        let paneBounds = CGRect(origin: .zero, size: pdfView.bounds.size)
        guard let passage,
              let document = pdfView.document,
              let page = document.page(at: passage.pageIndex) else {
            return ReaderElfGeometrySnapshot(paneBounds: paneBounds, pageFrame: nil, anchorFrame: nil)
        }

        let pageRect = pdfView.convert(page.bounds(for: pdfView.displayBox), from: page).standardized
        let anchorRect = passage.rects
            .map(\.cgRect)
            .reduce(CGRect.null) { partialResult, rect in
                partialResult.isNull ? rect : partialResult.union(rect)
            }
        let convertedAnchorRect = anchorRect.isNull ? nil : pdfView.convert(anchorRect, from: page).standardized

        return ReaderElfGeometrySnapshot(
            paneBounds: paneBounds,
            pageFrame: convertToTopLeading(pageRect, within: paneBounds.height),
            anchorFrame: convertedAnchorRect.map { convertToTopLeading($0, within: paneBounds.height) }
        )
    }

    private static func convertToTopLeading(_ rect: CGRect, within containerHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: containerHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        ).standardized
    }
}

struct ReaderElfOverlayState: Equatable {
    let status: ReaderElfStatus
    let activeComment: ReaderElfComment?
    let dockCorner: ReaderElfDockCorner
    let paneBounds: CGRect
    let pageFrame: CGRect?
    let anchorFrame: CGRect?
    let preferredBubblePlacement: ReaderElfBubblePlacement

    init(
        status: ReaderElfStatus,
        activeComment: ReaderElfComment?,
        dockCorner: ReaderElfDockCorner = .bottomRight,
        geometry: ReaderElfGeometrySnapshot?,
        preferredBubblePlacement: ReaderElfBubblePlacement = .above
    ) {
        self.status = status
        self.activeComment = activeComment
        self.dockCorner = dockCorner
        self.paneBounds = geometry?.paneBounds ?? .zero
        self.pageFrame = geometry?.pageFrame
        self.anchorFrame = geometry?.anchorFrame
        self.preferredBubblePlacement = preferredBubblePlacement
    }
}

struct ReaderElfBubbleStyle {
    static let pdfBodyReferenceColor = NSColor.black
    static let commentTextColor = NSColor(
        calibratedRed: 0.17,
        green: 0.26,
        blue: 0.35,
        alpha: 1
    )
    static let supportingTextColor = NSColor(
        calibratedRed: 0.42,
        green: 0.46,
        blue: 0.50,
        alpha: 1
    )

    let fillTopColor: NSColor
    let fillBottomColor: NSColor
    let borderColor: NSColor
    let accentColor: NSColor
    let tailColor: NSColor
    let textColor: NSColor
    let secondaryTextColor: NSColor

    static func make(for mood: ReaderElfMood) -> ReaderElfBubbleStyle {
        ReaderElfBubbleStyle(
            fillTopColor: NSColor(
                calibratedRed: 0.994,
                green: 0.978,
                blue: 0.946,
                alpha: 0.98
            ),
            fillBottomColor: NSColor(
                calibratedRed: 0.978,
                green: 0.956,
                blue: 0.918,
                alpha: 0.97
            ),
            borderColor: mood.accentColor.withAlphaComponent(0.34),
            accentColor: mood.accentColor,
            tailColor: NSColor(
                calibratedRed: 0.986,
                green: 0.967,
                blue: 0.932,
                alpha: 0.98
            ),
            textColor: commentTextColor,
            secondaryTextColor: supportingTextColor
        )
    }
}

struct ReaderElfOverlayLayout: Equatable {
    static let figureSize = CGSize(width: 58, height: 86)
    static let minimumBubbleWidth: CGFloat = 164
    static let maximumBubbleWidth: CGFloat = 212
    private static let outerPadding: CGFloat = 18
    private static let pageInset: CGFloat = 14
    private static let bubbleGap: CGFloat = 12
    private static let figureGap: CGFloat = 8
    private static let bubblePadding: CGFloat = 24
    private static let minimumBubbleHeight: CGFloat = 76
    private static let maximumBubbleHeight: CGFloat = 160
    private static let lineHeight: CGFloat = 15

    let figureFrame: CGRect
    let bubbleFrame: CGRect?
    let bubblePlacement: ReaderElfBubblePlacement?
    let tailTip: CGPoint?

    static func resolve(for state: ReaderElfOverlayState) -> ReaderElfOverlayLayout {
        let paneBounds = state.paneBounds.isEmpty
            ? CGRect(origin: .zero, size: CGSize(width: 760, height: 760))
            : state.paneBounds.standardized
        let dockFrame = dockFigureFrame(in: paneBounds, corner: state.dockCorner)

        guard let comment = state.activeComment,
              let pageFrame = state.pageFrame?.standardized,
              let anchorFrame = state.anchorFrame?.standardized,
              pageFrame.intersects(paneBounds),
              anchorFrame.intersects(paneBounds) else {
            return ReaderElfOverlayLayout(
                figureFrame: dockFrame,
                bubbleFrame: nil,
                bubblePlacement: nil,
                tailTip: nil
            )
        }

        let boundedPageFrame = pageFrame.insetBy(dx: pageInset, dy: pageInset)
        let boundedAnchorFrame = anchorFrame.intersection(pageFrame).standardized
        let bubbleWidth = min(
            boundedPageFrame.width,
            min(maximumBubbleWidth, max(minimumBubbleWidth, boundedPageFrame.width * 0.46))
        )
        let bubbleHeight = estimatedBubbleHeight(for: comment.text, width: bubbleWidth)
        let placementOrder = orderedPlacements(preferred: state.preferredBubblePlacement)
        let resolvedBubble = (placementOrder.lazy.compactMap {
            makeBubbleFrame(
                for: $0,
                anchorFrame: boundedAnchorFrame,
                pageFrame: boundedPageFrame,
                bubbleSize: CGSize(width: bubbleWidth, height: bubbleHeight),
                fitRequired: true
            )
        }.first ?? makeBubbleFrame(
            for: state.preferredBubblePlacement,
            anchorFrame: boundedAnchorFrame,
            pageFrame: boundedPageFrame,
            bubbleSize: CGSize(width: bubbleWidth, height: bubbleHeight),
            fitRequired: false
        ))!

        let bubbleFrame = resolvedBubble.frame.standardized
        let figureFrame = placeFigure(
            bubbleFrame: bubbleFrame,
            bubblePlacement: resolvedBubble.placement,
            anchorFrame: boundedAnchorFrame,
            pageFrame: boundedPageFrame
        )
        let tailTip = tailTip(
            for: bubbleFrame,
            placement: resolvedBubble.placement,
            anchorFrame: boundedAnchorFrame
        )

        return ReaderElfOverlayLayout(
            figureFrame: figureFrame,
            bubbleFrame: bubbleFrame,
            bubblePlacement: resolvedBubble.placement,
            tailTip: tailTip
        )
    }

    private static func orderedPlacements(preferred: ReaderElfBubblePlacement) -> [ReaderElfBubblePlacement] {
        let defaultOrder: [ReaderElfBubblePlacement] = [.above, .below, .trailing, .leading]
        return [preferred] + defaultOrder.filter { $0 != preferred }
    }

    private static func makeBubbleFrame(
        for placement: ReaderElfBubblePlacement,
        anchorFrame: CGRect,
        pageFrame: CGRect,
        bubbleSize: CGSize,
        fitRequired: Bool
    ) -> (placement: ReaderElfBubblePlacement, frame: CGRect)? {
        let width = bubbleSize.width
        let height = bubbleSize.height

        let centeredX = clamp(
            anchorFrame.midX - (width * 0.5),
            min: pageFrame.minX,
            max: pageFrame.maxX - width
        )
        let centeredY = clamp(
            anchorFrame.midY - (height * 0.5),
            min: pageFrame.minY,
            max: pageFrame.maxY - height
        )

        let frame: CGRect
        let fits: Bool
        switch placement {
        case .above:
            let y = anchorFrame.minY - bubbleGap - height
            frame = CGRect(x: centeredX, y: fitRequired ? y : clamp(y, min: pageFrame.minY, max: pageFrame.maxY - height), width: width, height: height)
            fits = y >= pageFrame.minY
        case .below:
            let y = anchorFrame.maxY + bubbleGap
            frame = CGRect(x: centeredX, y: fitRequired ? y : clamp(y, min: pageFrame.minY, max: pageFrame.maxY - height), width: width, height: height)
            fits = (y + height) <= pageFrame.maxY
        case .leading:
            let x = anchorFrame.minX - bubbleGap - width
            frame = CGRect(x: fitRequired ? x : clamp(x, min: pageFrame.minX, max: pageFrame.maxX - width), y: centeredY, width: width, height: height)
            fits = x >= pageFrame.minX
        case .trailing:
            let x = anchorFrame.maxX + bubbleGap
            frame = CGRect(x: fitRequired ? x : clamp(x, min: pageFrame.minX, max: pageFrame.maxX - width), y: centeredY, width: width, height: height)
            fits = (x + width) <= pageFrame.maxX
        }

        guard fitRequired == false || fits else {
            return nil
        }

        return (placement: placement, frame: frame.standardized)
    }

    private static func placeFigure(
        bubbleFrame: CGRect,
        bubblePlacement: ReaderElfBubblePlacement,
        anchorFrame: CGRect,
        pageFrame: CGRect
    ) -> CGRect {
        let initialFrame: CGRect
        switch bubblePlacement {
        case .above:
            initialFrame = CGRect(
                x: anchorFrame.midX - (figureSize.width * 0.35),
                y: bubbleFrame.maxY - (figureSize.height * 0.18),
                width: figureSize.width,
                height: figureSize.height
            )
        case .below:
            initialFrame = CGRect(
                x: anchorFrame.midX - (figureSize.width * 0.35),
                y: bubbleFrame.minY - figureSize.height + 10,
                width: figureSize.width,
                height: figureSize.height
            )
        case .leading:
            initialFrame = CGRect(
                x: bubbleFrame.maxX - (figureSize.width * 0.4),
                y: anchorFrame.maxY - (figureSize.height * 0.58),
                width: figureSize.width,
                height: figureSize.height
            )
        case .trailing:
            initialFrame = CGRect(
                x: bubbleFrame.minX - (figureSize.width * 0.6),
                y: anchorFrame.maxY - (figureSize.height * 0.58),
                width: figureSize.width,
                height: figureSize.height
            )
        }

        var clampedFrame = clamp(frame: initialFrame, within: pageFrame)
        if clampedFrame.intersects(bubbleFrame) {
            switch bubblePlacement {
            case .above:
                clampedFrame.origin.y = min(pageFrame.maxY - figureSize.height, bubbleFrame.maxY + figureGap)
            case .below:
                clampedFrame.origin.y = max(pageFrame.minY, bubbleFrame.minY - figureSize.height - figureGap)
            case .leading:
                clampedFrame.origin.x = min(pageFrame.maxX - figureSize.width, bubbleFrame.maxX + figureGap)
            case .trailing:
                clampedFrame.origin.x = max(pageFrame.minX, bubbleFrame.minX - figureSize.width - figureGap)
            }
            clampedFrame = clamp(frame: clampedFrame, within: pageFrame)
        }
        return clampedFrame.standardized
    }

    private static func tailTip(
        for bubbleFrame: CGRect,
        placement: ReaderElfBubblePlacement,
        anchorFrame: CGRect
    ) -> CGPoint {
        switch placement {
        case .above:
            return CGPoint(
                x: clamp(anchorFrame.midX, min: bubbleFrame.minX + 22, max: bubbleFrame.maxX - 22),
                y: bubbleFrame.maxY
            )
        case .below:
            return CGPoint(
                x: clamp(anchorFrame.midX, min: bubbleFrame.minX + 22, max: bubbleFrame.maxX - 22),
                y: bubbleFrame.minY
            )
        case .leading:
            return CGPoint(
                x: bubbleFrame.maxX,
                y: clamp(anchorFrame.midY, min: bubbleFrame.minY + 18, max: bubbleFrame.maxY - 18)
            )
        case .trailing:
            return CGPoint(
                x: bubbleFrame.minX,
                y: clamp(anchorFrame.midY, min: bubbleFrame.minY + 18, max: bubbleFrame.maxY - 18)
            )
        }
    }

    private static func dockFigureFrame(in paneBounds: CGRect, corner: ReaderElfDockCorner) -> CGRect {
        switch corner {
        case .bottomRight:
            return CGRect(
                x: paneBounds.maxX - figureSize.width - outerPadding,
                y: paneBounds.maxY - figureSize.height - outerPadding,
                width: figureSize.width,
                height: figureSize.height
            ).standardized
        }
    }

    private static func estimatedBubbleHeight(for text: String, width: CGFloat) -> CGFloat {
        let availableTextWidth = max(96, width - bubblePadding)
        let charactersPerLine = max(18, Int(availableTextWidth / 6.4))
        let lineCount = max(2, Int(ceil(Double(text.count) / Double(charactersPerLine))))
        let height = CGFloat(lineCount) * lineHeight + 42
        return min(maximumBubbleHeight, max(minimumBubbleHeight, height))
    }

    private static func clamp(frame: CGRect, within bounds: CGRect) -> CGRect {
        CGRect(
            x: clamp(frame.minX, min: bounds.minX, max: bounds.maxX - frame.width),
            y: clamp(frame.minY, min: bounds.minY, max: bounds.maxY - frame.height),
            width: frame.width,
            height: frame.height
        )
    }

    private static func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.max(minimum, Swift.min(maximum, value))
    }
}

struct ReaderPassageLine: Equatable, Sendable {
    let text: String
    let rect: ReaderAnnotationRect
}

enum ReaderFocusPassageExtractor {
    static func passage(from selection: ReaderSelectionSnapshot) -> ReaderFocusPassageSnapshot? {
        ReaderFocusPassageSnapshot(selection: selection)
    }

    @MainActor
    static func passage(in pdfView: PDFView) -> ReaderFocusPassageSnapshot? {
        guard let document = pdfView.document else { return nil }

        if let selection = pdfView.currentSelection,
           let snapshot = selectionSnapshot(from: selection, in: document),
           let passage = ReaderFocusPassageSnapshot(selection: snapshot) {
            return passage
        }

        let focusPoint = CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY)
        guard let page = pdfView.page(for: focusPoint, nearest: true) ?? pdfView.currentPage else {
            return nil
        }

        let pageIndex = document.index(for: page)
        guard pageIndex >= 0 else { return nil }

        let pointOnPage = pdfView.convert(focusPoint, to: page)
        return passage(on: page, pageIndex: pageIndex, around: pointOnPage)
    }

    static func passage(
        on page: PDFPage,
        pageIndex: Int,
        around point: CGPoint
    ) -> ReaderFocusPassageSnapshot? {
        let lines = lines(on: page)
        guard lines.isEmpty == false else { return nil }

        let centerIndex = nearestLineIndex(to: point, lines: lines)
        let clusteredLines = clusteredLines(around: centerIndex, lines: lines)
        let chosenLines = clusteredLines.count >= 2
            ? clusteredLines
            : fallbackLines(around: centerIndex, lines: lines)

        return passage(
            pageIndex: pageIndex,
            lines: chosenLines,
            source: .viewport
        )
    }

    static func lines(on page: PDFPage) -> [ReaderPassageLine] {
        let rawText = page.string ?? ""
        guard rawText.isEmpty == false else { return [] }

        let fullText = rawText as NSString
        var cursor = 0
        var lines: [ReaderPassageLine] = []

        while cursor < fullText.length {
            var lineStart = 0
            var lineEnd = 0
            var contentEnd = 0
            fullText.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentEnd, for: NSRange(location: cursor, length: 0))

            let contentRange = NSRange(location: lineStart, length: max(0, contentEnd - lineStart))
            let lineText = fullText.substring(with: contentRange).normalizedReaderContent

            if lineText.isEmpty == false,
               let selection = page.selection(for: contentRange) {
                selection.extendForLineBoundaries()
                let rect = selection.bounds(for: page).standardized
                if rect.width > 0.01, rect.height > 0.01 {
                    lines.append(
                        ReaderPassageLine(
                            text: lineText,
                            rect: ReaderAnnotationRect(rect: rect)
                        )
                    )
                }
            }

            cursor = max(lineEnd, cursor + 1)
        }

        return lines.sorted { lhs, rhs in
            let leftRect = lhs.rect.cgRect
            let rightRect = rhs.rect.cgRect
            if abs(leftRect.midY - rightRect.midY) > 0.5 {
                return leftRect.midY > rightRect.midY
            }
            return leftRect.minX < rightRect.minX
        }
    }

    static func clusteredLines(
        around centerIndex: Int,
        lines: [ReaderPassageLine]
    ) -> [ReaderPassageLine] {
        guard lines.indices.contains(centerIndex) else { return [] }

        var lowerBound = centerIndex
        while lowerBound > 0 {
            let candidate = lines[lowerBound - 1]
            let anchor = lines[lowerBound]
            guard shouldCluster(upper: candidate, lower: anchor) else { break }
            lowerBound -= 1
        }

        var upperBound = centerIndex
        while upperBound < lines.count - 1 {
            let anchor = lines[upperBound]
            let candidate = lines[upperBound + 1]
            guard shouldCluster(upper: anchor, lower: candidate) else { break }
            upperBound += 1
        }

        return Array(lines[lowerBound...upperBound])
    }

    static func fallbackLines(
        around centerIndex: Int,
        lines: [ReaderPassageLine],
        radius: Int = 2
    ) -> [ReaderPassageLine] {
        guard lines.indices.contains(centerIndex) else { return [] }
        let startIndex = max(0, centerIndex - radius)
        let endIndex = min(lines.count - 1, centerIndex + radius)
        return Array(lines[startIndex...endIndex])
    }

    static func nearestLineIndex(
        to point: CGPoint,
        lines: [ReaderPassageLine]
    ) -> Int {
        guard lines.isEmpty == false else { return 0 }

        return lines.enumerated().min { lhs, rhs in
            distance(to: point, rect: lhs.element.rect.cgRect) < distance(to: point, rect: rhs.element.rect.cgRect)
        }?.offset ?? 0
    }

    private static func passage(
        pageIndex: Int,
        lines: [ReaderPassageLine],
        source: ReaderFocusPassageSource
    ) -> ReaderFocusPassageSnapshot? {
        ReaderFocusPassageSnapshot(
            pageIndex: pageIndex,
            quotedText: lines.map(\.text).joined(separator: " "),
            rects: lines.map(\.rect),
            source: source
        )
    }

    private static func distance(to point: CGPoint, rect: CGRect) -> CGFloat {
        let verticalDistance: CGFloat
        if rect.minY...rect.maxY ~= point.y {
            verticalDistance = 0
        } else {
            verticalDistance = min(abs(point.y - rect.minY), abs(point.y - rect.maxY))
        }

        let horizontalDistance: CGFloat
        if rect.minX...rect.maxX ~= point.x {
            horizontalDistance = 0
        } else {
            horizontalDistance = min(abs(point.x - rect.minX), abs(point.x - rect.maxX))
        }

        return (verticalDistance * 3) + horizontalDistance
    }

    private static func shouldCluster(upper: ReaderPassageLine, lower: ReaderPassageLine) -> Bool {
        let upperRect = upper.rect.cgRect
        let lowerRect = lower.rect.cgRect
        let verticalGap = upperRect.minY - lowerRect.maxY
        let maxHeight = max(upperRect.height, lowerRect.height)
        let leftDelta = abs(upperRect.minX - lowerRect.minX)
        let widthRatio = min(upperRect.width, lowerRect.width) / max(upperRect.width, lowerRect.width)

        return verticalGap <= max(18, maxHeight * 1.2)
            && leftDelta <= 28
            && (widthRatio >= 0.35 || leftDelta <= 12)
    }

    private static func selectionSnapshot(
        from selection: PDFSelection,
        in document: PDFDocument
    ) -> ReaderSelectionSnapshot? {
        let pageIndexes = Set(
            selection.pages
                .map { document.index(for: $0) }
                .filter { $0 >= 0 && $0 < document.pageCount }
        )

        guard pageIndexes.count == 1,
              let pageIndex = pageIndexes.first,
              let page = document.page(at: pageIndex) else {
            return nil
        }

        let lineSelections = selection.selectionsByLine()
            .filter { lineSelection in
                lineSelection.pages.contains(where: { document.index(for: $0) == pageIndex })
            }
        let rects = lineSelections.isEmpty
            ? [selection.bounds(for: page).standardized]
            : lineSelections.map { $0.bounds(for: page).standardized }

        return ReaderSelectionSnapshot(
            pageIndex: pageIndex,
            quotedText: selection.string ?? "",
            rects: rects
        )
    }
}

extension PaperAnnotation {
    var jumpTarget: ReaderPassageJumpTarget {
        ReaderPassageJumpTarget(pageIndex: pageIndex, rects: rects)
    }
}
