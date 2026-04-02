import AppKit
import SwiftUI
import XCTest
@testable import PaperMasterShared

final class ReaderMarginAnnotationLayoutTests: XCTestCase {
    private let paneBounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let pageFrame = CGRect(x: 100, y: 50, width: 600, height: 700)

    private func makeEntry(
        id: UUID = UUID(),
        unionRect: CGRect,
        anchorY: CGFloat? = nil,
        color: ReaderHighlightColor = .yellow
    ) -> ReaderMarginAnnotationGeometry.Entry {
        let anchor = anchorY ?? unionRect.midY
        return ReaderMarginAnnotationGeometry.Entry(
            id: id,
            annotationColor: color,
            highlightUnionRect: unionRect,
            idealAnchorY: anchor
        )
    }

    private func makeAnnotation(noteText: String = "Short note") -> PaperAnnotation {
        let paper = Paper(title: "Margin Annotation Test Paper")
        return PaperAnnotation(
            paper: paper,
            pageIndex: 0,
            quotedText: "Quoted passage",
            noteText: noteText,
            rectPayload: ReaderRectPayloadCodec.encode([CGRect(x: 10, y: 10, width: 40, height: 12)])
        )
    }

    func testSingleAnnotationPlacedAtIdealPosition() {
        let entry = makeEntry(unionRect: CGRect(x: 200, y: 300, width: 400, height: 20))
        let geometry = ReaderMarginAnnotationGeometry(
            paneBounds: paneBounds,
            rightmostPageFrame: pageFrame,
            entries: [entry]
        )

        let layout = ReaderMarginAnnotationLayout.resolve(
            geometry: geometry,
            expandedCardID: nil,
            cardHeights: [:]
        )

        XCTAssertEqual(layout.cards.count, 1)
        let card = layout.cards[0]
        XCTAssertEqual(card.id, entry.id)
        XCTAssertEqual(card.cardFrame.minX, pageFrame.maxX + ReaderMarginAnnotationLayout.marginGap)
        XCTAssertEqual(card.cardFrame.width, ReaderMarginAnnotationLayout.cardWidth)
    }

    func testEmptyEntriesProducesNoCards() {
        let geometry = ReaderMarginAnnotationGeometry(
            paneBounds: paneBounds,
            rightmostPageFrame: pageFrame,
            entries: []
        )

        let layout = ReaderMarginAnnotationLayout.resolve(
            geometry: geometry,
            expandedCardID: nil,
            cardHeights: [:]
        )

        XCTAssertTrue(layout.cards.isEmpty)
    }

    func testNilPageFrameProducesNoCards() {
        let entry = makeEntry(unionRect: CGRect(x: 200, y: 300, width: 400, height: 20))
        let geometry = ReaderMarginAnnotationGeometry(
            paneBounds: paneBounds,
            rightmostPageFrame: nil,
            entries: [entry]
        )

        let layout = ReaderMarginAnnotationLayout.resolve(
            geometry: geometry,
            expandedCardID: nil,
            cardHeights: [:]
        )

        XCTAssertTrue(layout.cards.isEmpty)
    }

    func testOverlappingAnnotationsPushDown() {
        let entry1 = makeEntry(
            unionRect: CGRect(x: 200, y: 300, width: 400, height: 20),
            anchorY: 310
        )
        let entry2 = makeEntry(
            unionRect: CGRect(x: 200, y: 320, width: 400, height: 20),
            anchorY: 330
        )

        let geometry = ReaderMarginAnnotationGeometry(
            paneBounds: paneBounds,
            rightmostPageFrame: pageFrame,
            entries: [entry1, entry2]
        )

        let layout = ReaderMarginAnnotationLayout.resolve(
            geometry: geometry,
            expandedCardID: nil,
            cardHeights: [:]
        )

        XCTAssertEqual(layout.cards.count, 2)
        let card1 = layout.cards[0]
        let card2 = layout.cards[1]
        let gap = card2.cardFrame.minY - card1.cardFrame.maxY
        XCTAssertEqual(gap, ReaderMarginAnnotationLayout.cardGap, accuracy: 0.01)
    }

    func testLeaderStartPointIsAtHighlightRightEdge() {
        let highlightRect = CGRect(x: 200, y: 300, width: 400, height: 20)
        let entry = makeEntry(unionRect: highlightRect)
        let geometry = ReaderMarginAnnotationGeometry(
            paneBounds: paneBounds,
            rightmostPageFrame: pageFrame,
            entries: [entry]
        )

        let layout = ReaderMarginAnnotationLayout.resolve(
            geometry: geometry,
            expandedCardID: nil,
            cardHeights: [:]
        )

        let card = layout.cards[0]
        XCTAssertEqual(card.leaderStartPoint.x, highlightRect.maxX + 2, accuracy: 0.01)
        XCTAssertEqual(card.leaderStartPoint.y, highlightRect.midY, accuracy: 0.01)
    }

    func testLeaderEndPointIsAtCardLeftEdge() {
        let entry = makeEntry(unionRect: CGRect(x: 200, y: 300, width: 400, height: 20))
        let geometry = ReaderMarginAnnotationGeometry(
            paneBounds: paneBounds,
            rightmostPageFrame: pageFrame,
            entries: [entry]
        )

        let layout = ReaderMarginAnnotationLayout.resolve(
            geometry: geometry,
            expandedCardID: nil,
            cardHeights: [:]
        )

        let card = layout.cards[0]
        XCTAssertEqual(card.leaderEndPoint.x, card.cardFrame.minX, accuracy: 0.01)
    }

    func testNarrowMarginUsesCompactWidth() {
        let narrowPane = CGRect(x: 0, y: 0, width: 750, height: 800)
        let widePageFrame = CGRect(x: 50, y: 50, width: 600, height: 700)

        let entry = makeEntry(unionRect: CGRect(x: 200, y: 300, width: 400, height: 20))
        let geometry = ReaderMarginAnnotationGeometry(
            paneBounds: narrowPane,
            rightmostPageFrame: widePageFrame,
            entries: [entry]
        )

        let layout = ReaderMarginAnnotationLayout.resolve(
            geometry: geometry,
            expandedCardID: nil,
            cardHeights: [:]
        )

        XCTAssertEqual(layout.cards.count, 1)
        XCTAssertTrue(layout.cards[0].isCompact)
    }

    func testExpandedCardGetsMoreHeight() {
        let id = UUID()
        let entry = makeEntry(
            id: id,
            unionRect: CGRect(x: 200, y: 300, width: 400, height: 20)
        )
        let geometry = ReaderMarginAnnotationGeometry(
            paneBounds: paneBounds,
            rightmostPageFrame: pageFrame,
            entries: [entry]
        )

        let collapsedLayout = ReaderMarginAnnotationLayout.resolve(
            geometry: geometry,
            expandedCardID: nil,
            cardHeights: [:]
        )

        let expandedLayout = ReaderMarginAnnotationLayout.resolve(
            geometry: geometry,
            expandedCardID: id,
            cardHeights: [:]
        )

        XCTAssertGreaterThan(
            expandedLayout.cards[0].cardFrame.height,
            collapsedLayout.cards[0].cardFrame.height
        )
    }

    func testCardsPreserveAnnotationColor() {
        let entry1 = makeEntry(
            unionRect: CGRect(x: 200, y: 200, width: 400, height: 20),
            color: .yellow
        )
        let entry2 = makeEntry(
            unionRect: CGRect(x: 200, y: 500, width: 400, height: 20),
            color: .pink
        )

        let geometry = ReaderMarginAnnotationGeometry(
            paneBounds: paneBounds,
            rightmostPageFrame: pageFrame,
            entries: [entry1, entry2]
        )

        let layout = ReaderMarginAnnotationLayout.resolve(
            geometry: geometry,
            expandedCardID: nil,
            cardHeights: [:]
        )

        XCTAssertEqual(layout.cards[0].annotationColor, .yellow)
        XCTAssertEqual(layout.cards[1].annotationColor, .pink)
    }

    func testWidelySpacedAnnotationsAreCappedAtMaxGap() {
        let entry1 = makeEntry(
            unionRect: CGRect(x: 200, y: 100, width: 400, height: 20),
            anchorY: 110
        )
        let entry2 = makeEntry(
            unionRect: CGRect(x: 200, y: 500, width: 400, height: 20),
            anchorY: 510
        )

        let geometry = ReaderMarginAnnotationGeometry(
            paneBounds: paneBounds,
            rightmostPageFrame: pageFrame,
            entries: [entry1, entry2]
        )

        let layout = ReaderMarginAnnotationLayout.resolve(
            geometry: geometry,
            expandedCardID: nil,
            cardHeights: [:]
        )

        XCTAssertEqual(layout.cards.count, 2)
        let gap = layout.cards[1].cardFrame.minY - layout.cards[0].cardFrame.maxY
        XCTAssertEqual(gap, ReaderMarginAnnotationLayout.maxGap, accuracy: 0.01)
    }

    func testMarginLayoutUsesTightSpacingDefaults() {
        XCTAssertEqual(ReaderMarginAnnotationLayout.cardGap, 4)
        XCTAssertEqual(ReaderMarginAnnotationLayout.maxGap, 12)
    }

    func testManyAnnotationsAllFitWithinPane() {
        var entries: [ReaderMarginAnnotationGeometry.Entry] = []
        for i in 0..<20 {
            entries.append(makeEntry(
                unionRect: CGRect(x: 200, y: CGFloat(60 + i * 35), width: 400, height: 15),
                anchorY: CGFloat(67 + i * 35)
            ))
        }

        let geometry = ReaderMarginAnnotationGeometry(
            paneBounds: paneBounds,
            rightmostPageFrame: pageFrame,
            entries: entries
        )

        let layout = ReaderMarginAnnotationLayout.resolve(
            geometry: geometry,
            expandedCardID: nil,
            cardHeights: [:]
        )

        for card in layout.cards {
            XCTAssertGreaterThanOrEqual(card.cardFrame.minY, paneBounds.minY)
        }

        for i in 1..<layout.cards.count {
            let prev = layout.cards[i - 1]
            let curr = layout.cards[i]
            XCTAssertGreaterThanOrEqual(
                curr.cardFrame.minY, prev.cardFrame.maxY,
                "Card \(i) overlaps card \(i - 1)"
            )
        }
    }

    @MainActor
    func testCollapsedMarginCardStaysContentSizedInsideTallContainer() {
        let annotation = makeAnnotation()

        let collapsedHeight = measureCardHeight(
            annotation: annotation,
            isExpanded: false,
            containerHeight: 320
        )
        XCTAssertGreaterThan(collapsedHeight, 20)
        XCTAssertLessThan(collapsedHeight, 90)

        let expandedHeight = measureCardHeight(
            annotation: annotation,
            isExpanded: true,
            containerHeight: 320
        )
        XCTAssertGreaterThan(expandedHeight, ReaderMarginAnnotationLayout.expandedMinHeight - 1)
        XCTAssertGreaterThan(expandedHeight, collapsedHeight)
    }

    @MainActor
    private func measureCardHeight(
        annotation: PaperAnnotation,
        isExpanded: Bool,
        containerHeight: CGFloat
    ) -> CGFloat {
        var measuredHeight: CGFloat = 0
        let host = NSHostingView(
            rootView: MarginCardMeasurementHost(
                annotation: annotation,
                isExpanded: isExpanded,
                containerHeight: containerHeight,
                onHeightChange: { measuredHeight = $0 }
            )
        )
        host.frame = CGRect(
            x: 0,
            y: 0,
            width: ReaderMarginAnnotationLayout.cardWidth,
            height: containerHeight
        )

        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()

        let deadline = Date().addingTimeInterval(0.5)
        while measuredHeight == 0, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            host.layoutSubtreeIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()
        }

        return measuredHeight
    }
}

private struct MarginCardMeasurementHost: View {
    let annotation: PaperAnnotation
    let isExpanded: Bool
    let containerHeight: CGFloat
    let onHeightChange: (CGFloat) -> Void

    @State private var noteText: String
    @FocusState private var focusedField: ReaderMarginFocusField?

    init(
        annotation: PaperAnnotation,
        isExpanded: Bool,
        containerHeight: CGFloat,
        onHeightChange: @escaping (CGFloat) -> Void
    ) {
        self.annotation = annotation
        self.isExpanded = isExpanded
        self.containerHeight = containerHeight
        self.onHeightChange = onHeightChange
        _noteText = State(initialValue: annotation.noteText)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ReaderMarginAnnotationCard(
                annotation: annotation,
                isExpanded: isExpanded,
                isSpotlighted: false,
                isCompact: false,
                noteBinding: $noteText,
                focusedField: $focusedField,
                onTap: {},
                onJump: {},
                onDelete: {},
                onColorChange: { _ in },
                onNoteFocusChanged: { _ in }
            )
            .frame(width: ReaderMarginAnnotationLayout.cardWidth)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            onHeightChange(proxy.size.height)
                        }
                        .onChange(of: proxy.size.height) { _, newValue in
                            onHeightChange(newValue)
                        }
                }
            )
        }
        .frame(
            width: ReaderMarginAnnotationLayout.cardWidth,
            height: containerHeight,
            alignment: .topLeading
        )
    }
}
