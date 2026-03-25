import Foundation
import PDFKit

enum ReaderAnnotationDisplayMode: String, CaseIterable {
    case sidebar
    case margin
}

struct ReaderMarginAnnotationGeometry: Equatable {
    struct Entry: Equatable, Identifiable {
        let id: UUID
        let annotationColor: ReaderHighlightColor
        let highlightUnionRect: CGRect
        let idealAnchorY: CGFloat
    }

    let paneBounds: CGRect
    let rightmostPageFrame: CGRect?
    let entries: [Entry]

    @MainActor
    static func capture(
        annotations: [PaperAnnotation],
        in pdfView: PDFView
    ) -> ReaderMarginAnnotationGeometry {
        let paneBounds = CGRect(origin: .zero, size: pdfView.bounds.size)
        guard let document = pdfView.document else {
            return ReaderMarginAnnotationGeometry(
                paneBounds: paneBounds,
                rightmostPageFrame: nil,
                entries: []
            )
        }

        let visiblePages = pdfView.visiblePages
        let visibleIndexes = Set(visiblePages.map { document.index(for: $0) })

        var rightmostPageFrame: CGRect?
        for page in visiblePages {
            let pageRect = pdfView.convert(page.bounds(for: pdfView.displayBox), from: page).standardized
            let viewRect = pageRect.convertedToTopLeading(within: paneBounds.height)
            if let existing = rightmostPageFrame {
                if viewRect.maxX > existing.maxX {
                    rightmostPageFrame = viewRect
                }
            } else {
                rightmostPageFrame = viewRect
            }
        }

        let visibleAnnotations = annotations
            .filter { visibleIndexes.contains($0.pageIndex) }
            .sorted(by: PaperAnnotation.sidebarSort)

        var entries: [Entry] = []
        for annotation in visibleAnnotations {
            guard let page = document.page(at: annotation.pageIndex) else { continue }

            let lineRects = annotation.rects
                .map(\.cgRect)
                .map { pdfView.convert($0, from: page).standardized }
                .map { $0.convertedToTopLeading(within: paneBounds.height) }
                .filter { $0.width > 0.01 && $0.height > 0.01 }

            guard lineRects.isEmpty == false else { continue }

            let unionRect = lineRects.unionRect.standardized

            let clippedUnion = unionRect.intersection(paneBounds)
            guard clippedUnion.isNull == false else { continue }

            entries.append(Entry(
                id: annotation.id,
                annotationColor: annotation.color,
                highlightUnionRect: unionRect,
                idealAnchorY: clippedUnion.midY
            ))
        }

        entries.sort { $0.idealAnchorY < $1.idealAnchorY }

        return ReaderMarginAnnotationGeometry(
            paneBounds: paneBounds,
            rightmostPageFrame: rightmostPageFrame,
            entries: entries
        )
    }

}

struct ReaderMarginAnnotationLayout: Equatable {
    struct CardLayout: Equatable, Identifiable {
        let id: UUID
        let cardFrame: CGRect
        let leaderStartPoint: CGPoint
        let leaderEndPoint: CGPoint
        let annotationColor: ReaderHighlightColor
        let isCompact: Bool
    }

    static let cardWidth: CGFloat = 170
    static let compactCardWidth: CGFloat = 120
    static let cardGap: CGFloat = 4
    static let maxGap: CGFloat = 12
    static let marginGap: CGFloat = 10
    static let minimumMarginWidth: CGFloat = 180
    static let compactThreshold: CGFloat = 100
    static let defaultCardHeight: CGFloat = 36
    static let expandedMinHeight: CGFloat = 100

    let cards: [CardLayout]

    static func resolve(
        geometry: ReaderMarginAnnotationGeometry,
        expandedCardID: UUID?,
        cardHeights: [UUID: CGFloat]
    ) -> ReaderMarginAnnotationLayout {
        guard let pageFrame = geometry.rightmostPageFrame,
              geometry.entries.isEmpty == false else {
            return ReaderMarginAnnotationLayout(cards: [])
        }

        let availableMargin = geometry.paneBounds.maxX - pageFrame.maxX
        let isCompact = availableMargin < minimumMarginWidth
        let effectiveWidth = isCompact ? compactCardWidth : cardWidth

        let marginX: CGFloat
        if availableMargin >= minimumMarginWidth {
            marginX = pageFrame.maxX + marginGap
        } else if availableMargin >= compactThreshold {
            marginX = geometry.paneBounds.maxX - effectiveWidth - 8
        } else {
            marginX = pageFrame.maxX - effectiveWidth * 0.3
        }

        let clampedMaxX = geometry.paneBounds.maxX - 4
        let clampedWidth = min(effectiveWidth, clampedMaxX - marginX)
        guard clampedWidth > 40 else {
            return ReaderMarginAnnotationLayout(cards: [])
        }

        var cards: [CardLayout] = []
        var nextMinY: CGFloat = max(geometry.paneBounds.minY + 4, pageFrame.minY)

        for entry in geometry.entries {
            let isExpanded = expandedCardID == entry.id
            let estimatedHeight: CGFloat
            if isExpanded {
                estimatedHeight = max(
                    cardHeights[entry.id] ?? expandedMinHeight,
                    expandedMinHeight
                )
            } else {
                estimatedHeight = cardHeights[entry.id] ?? defaultCardHeight
            }

            var cardY = entry.idealAnchorY - estimatedHeight / 2
            if cardY < nextMinY {
                cardY = nextMinY
            }

            let maxY = geometry.paneBounds.maxY - estimatedHeight - 4
            if cardY > maxY && maxY >= nextMinY {
                cardY = maxY
            }

            let cardFrame = CGRect(
                x: marginX,
                y: cardY,
                width: clampedWidth,
                height: estimatedHeight
            )

            let leaderStart = CGPoint(
                x: entry.highlightUnionRect.maxX + 2,
                y: entry.highlightUnionRect.midY
            )
            let leaderEnd = CGPoint(
                x: cardFrame.minX,
                y: cardFrame.minY + min(20, estimatedHeight / 2)
            )

            cards.append(CardLayout(
                id: entry.id,
                cardFrame: cardFrame,
                leaderStartPoint: leaderStart,
                leaderEndPoint: leaderEnd,
                annotationColor: entry.annotationColor,
                isCompact: isCompact
            ))

            nextMinY = cardFrame.maxY + cardGap
        }

        // Pull cards closer when the gap between consecutive cards exceeds maxGap.
        var totalPullUp: CGFloat = 0
        for i in 1..<cards.count {
            if totalPullUp > 0 {
                let card = cards[i]
                let newFrame = card.cardFrame.offsetBy(dx: 0, dy: -totalPullUp)
                let newLeaderEnd = CGPoint(x: card.leaderEndPoint.x, y: card.leaderEndPoint.y - totalPullUp)
                cards[i] = CardLayout(id: card.id, cardFrame: newFrame, leaderStartPoint: card.leaderStartPoint, leaderEndPoint: newLeaderEnd, annotationColor: card.annotationColor, isCompact: card.isCompact)
            }
            let gap = cards[i].cardFrame.minY - cards[i - 1].cardFrame.maxY
            if gap > maxGap {
                let extra = gap - maxGap
                totalPullUp += extra
                let card = cards[i]
                let newFrame = card.cardFrame.offsetBy(dx: 0, dy: -extra)
                let newLeaderEnd = CGPoint(x: card.leaderEndPoint.x, y: card.leaderEndPoint.y - extra)
                cards[i] = CardLayout(id: card.id, cardFrame: newFrame, leaderStartPoint: card.leaderStartPoint, leaderEndPoint: newLeaderEnd, annotationColor: card.annotationColor, isCompact: card.isCompact)
            }
        }

        if let lastCard = cards.last,
           lastCard.cardFrame.maxY > geometry.paneBounds.maxY - 4 {
            compressCards(&cards, within: geometry.paneBounds)
        }

        return ReaderMarginAnnotationLayout(cards: cards)
    }

    private static func compressCards(
        _ cards: inout [CardLayout],
        within paneBounds: CGRect
    ) {
        guard cards.count >= 2 else { return }

        let totalOverflow = (cards.last?.cardFrame.maxY ?? 0) - (paneBounds.maxY - 4)
        guard totalOverflow > 0 else { return }

        let gapCount = CGFloat(cards.count - 1)
        guard gapCount > 0 else { return }

        let reductionPerGap = min(totalOverflow / gapCount, cardGap - 1)
        var offset: CGFloat = 0

        for i in 0..<cards.count {
            if i > 0 {
                offset += reductionPerGap
            }

            let card = cards[i]
            let newFrame = card.cardFrame.offsetBy(dx: 0, dy: -offset)
            let newLeaderEnd = CGPoint(
                x: card.leaderEndPoint.x,
                y: card.leaderEndPoint.y - offset
            )

            cards[i] = CardLayout(
                id: card.id,
                cardFrame: newFrame,
                leaderStartPoint: card.leaderStartPoint,
                leaderEndPoint: newLeaderEnd,
                annotationColor: card.annotationColor,
                isCompact: card.isCompact
            )
        }
    }
}
