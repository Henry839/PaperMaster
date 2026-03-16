import AppKit
import CoreGraphics
import XCTest
@testable import PaperMaster

final class ReaderCompanionTests: XCTestCase {
    func testSessionCapsRecentCommentsAndKeepsNewestFirst() throws {
        var session = ReaderElfSessionState()

        for index in 0..<6 {
            let comment = ReaderElfComment(
                passage: try passage(pageIndex: index, text: "Passage \(index)"),
                mood: .skeptical,
                text: "Comment \(index)",
                createdAt: Date(timeIntervalSince1970: Double(index))
            )
            session.surface(comment, cooldown: 0)
        }

        XCTAssertEqual(session.recentComments.count, 5)
        XCTAssertEqual(session.recentComments.first?.text, "Comment 5")
        XCTAssertEqual(session.recentComments.last?.text, "Comment 1")
    }

    func testSessionDoesNotEvaluateSamePassageTwiceInARow() throws {
        var session = ReaderElfSessionState()
        let firstPassage = try passage(pageIndex: 0, text: "A method claim")
        let secondPassage = try passage(pageIndex: 0, text: "A different baseline claim")

        session.finishWithoutComment(for: firstPassage)

        XCTAssertFalse(session.canEvaluate(firstPassage))
        XCTAssertTrue(session.canEvaluate(secondPassage))
    }

    func testSessionReportsCooldownStatusUntilDeadline() throws {
        var session = ReaderElfSessionState()
        let createdAt = Date(timeIntervalSince1970: 100)
        let comment = ReaderElfComment(
            passage: try passage(pageIndex: 0, text: "A weak ablation"),
            mood: .alarmed,
            text: "This control looks missing.",
            createdAt: createdAt
        )

        session.surface(comment, cooldown: 45)

        guard case let .coolingDown(until) = session.status(now: createdAt.addingTimeInterval(10)) else {
            return XCTFail("Expected cooldown status.")
        }

        XCTAssertEqual(until, createdAt.addingTimeInterval(45))
        XCTAssertEqual(session.status(now: createdAt.addingTimeInterval(46)), .listening)
    }

    func testClusteredLinesStopAtLargeParagraphGap() {
        let lines = [
            line(text: "First line", x: 40, y: 680, width: 260, height: 14),
            line(text: "Second line", x: 42, y: 660, width: 256, height: 14),
            line(text: "Paragraph two", x: 40, y: 600, width: 260, height: 14)
        ]

        let clustered = ReaderFocusPassageExtractor.clusteredLines(around: 1, lines: lines)

        XCTAssertEqual(clustered.map(\.text), ["First line", "Second line"])
    }

    func testFallbackLinesReturnLocalWindowAroundCenter() {
        let lines = [
            line(text: "L0", x: 40, y: 700, width: 260, height: 14),
            line(text: "L1", x: 40, y: 680, width: 260, height: 14),
            line(text: "L2", x: 40, y: 660, width: 260, height: 14),
            line(text: "L3", x: 40, y: 640, width: 260, height: 14),
            line(text: "L4", x: 40, y: 620, width: 260, height: 14),
            line(text: "L5", x: 40, y: 600, width: 260, height: 14)
        ]

        let fallback = ReaderFocusPassageExtractor.fallbackLines(around: 2, lines: lines)

        XCTAssertEqual(fallback.map(\.text), ["L0", "L1", "L2", "L3", "L4"])
    }

    func testOverlayLayoutPrefersAbovePlacementWhenThereIsRoom() throws {
        let geometry = ReaderElfGeometrySnapshot(
            paneBounds: CGRect(x: 0, y: 0, width: 920, height: 720),
            pageFrame: CGRect(x: 170, y: 48, width: 470, height: 610),
            anchorFrame: CGRect(x: 320, y: 318, width: 120, height: 40)
        )

        let layout = ReaderElfOverlayLayout.resolve(
            for: ReaderElfOverlayState(
                status: .coolingDown(until: .now),
                activeComment: try comment(text: "This claim leans hard on an underspecified baseline."),
                geometry: geometry
            )
        )

        XCTAssertEqual(layout.bubblePlacement, .above)
        XCTAssertLessThan(try XCTUnwrap(layout.bubbleFrame).maxY, try XCTUnwrap(geometry.anchorFrame).minY)
    }

    func testOverlayLayoutFallsBackToBelowWhenTopEdgeIsConstrained() throws {
        let geometry = ReaderElfGeometrySnapshot(
            paneBounds: CGRect(x: 0, y: 0, width: 920, height: 720),
            pageFrame: CGRect(x: 240, y: 48, width: 560, height: 610),
            anchorFrame: CGRect(x: 420, y: 72, width: 120, height: 40)
        )

        let layout = ReaderElfOverlayLayout.resolve(
            for: ReaderElfOverlayState(
                status: .coolingDown(until: .now),
                activeComment: try comment(text: "The empirical story ignores the compute budget entirely."),
                geometry: geometry
            )
        )

        XCTAssertEqual(layout.bubblePlacement, .below)
        XCTAssertGreaterThan(try XCTUnwrap(layout.bubbleFrame).minY, try XCTUnwrap(geometry.anchorFrame).maxY)
    }

    func testOverlayLayoutUsesSideFallbackWhenVerticalPlacementsAreConstrained() throws {
        let geometry = ReaderElfGeometrySnapshot(
            paneBounds: CGRect(x: 0, y: 0, width: 760, height: 420),
            pageFrame: CGRect(x: 120, y: 48, width: 420, height: 212),
            anchorFrame: CGRect(x: 172, y: 112, width: 96, height: 34)
        )

        let layout = ReaderElfOverlayLayout.resolve(
            for: ReaderElfOverlayState(
                status: .coolingDown(until: .now),
                activeComment: try comment(text: "The paragraph leaps from anecdote to mechanism without showing the bridge."),
                geometry: geometry
            )
        )

        XCTAssertEqual(layout.bubblePlacement, .trailing)
        XCTAssertGreaterThan(try XCTUnwrap(layout.bubbleFrame).minX, try XCTUnwrap(geometry.anchorFrame).maxX)
    }

    func testOverlayLayoutClampsBubbleWithinVisiblePageBoundsWhenNoPlacementFullyFits() throws {
        let geometry = ReaderElfGeometrySnapshot(
            paneBounds: CGRect(x: 0, y: 0, width: 520, height: 360),
            pageFrame: CGRect(x: 116, y: 56, width: 196, height: 132),
            anchorFrame: CGRect(x: 154, y: 84, width: 72, height: 26)
        )

        let layout = ReaderElfOverlayLayout.resolve(
            for: ReaderElfOverlayState(
                status: .coolingDown(until: .now),
                activeComment: try comment(text: "A long critique that still should not cover the paper when the margins are cramped."),
                geometry: geometry
            )
        )

        XCTAssertEqual(layout.bubblePlacement, .above)
        XCTAssertNotNil(layout.bubbleFrame)
        XCTAssertTrue(try XCTUnwrap(geometry.pageFrame).contains(try XCTUnwrap(layout.bubbleFrame)))
    }

    func testOverlayLayoutKeepsFigureDockedWhenElfIsOff() {
        let geometry = ReaderElfGeometrySnapshot(
            paneBounds: CGRect(x: 0, y: 0, width: 820, height: 620),
            pageFrame: nil,
            anchorFrame: nil
        )

        let layout = ReaderElfOverlayLayout.resolve(
            for: ReaderElfOverlayState(
                status: .off,
                activeComment: nil,
                geometry: geometry
            )
        )

        XCTAssertNil(layout.bubbleFrame)
        XCTAssertEqual(layout.figureFrame.minX, 744, accuracy: 0.001)
        XCTAssertEqual(layout.figureFrame.minY, 516, accuracy: 0.001)
    }

    func testOverlayLayoutReturnsToDockAfterCommentDismissal() throws {
        let geometry = ReaderElfGeometrySnapshot(
            paneBounds: CGRect(x: 0, y: 0, width: 900, height: 700),
            pageFrame: CGRect(x: 190, y: 52, width: 470, height: 580),
            anchorFrame: CGRect(x: 342, y: 300, width: 140, height: 44)
        )

        let activeLayout = ReaderElfOverlayLayout.resolve(
            for: ReaderElfOverlayState(
                status: .coolingDown(until: .now),
                activeComment: try comment(text: "This ablation matrix is too thin for the strength of the claim."),
                geometry: geometry
            )
        )
        let idleLayout = ReaderElfOverlayLayout.resolve(
            for: ReaderElfOverlayState(
                status: .listening,
                activeComment: nil,
                geometry: geometry
            )
        )

        XCTAssertNotEqual(activeLayout.figureFrame, idleLayout.figureFrame)
        XCTAssertNil(idleLayout.bubbleFrame)
        XCTAssertEqual(idleLayout.figureFrame.maxX, geometry.paneBounds.maxX - 18, accuracy: 0.001)
        XCTAssertEqual(idleLayout.figureFrame.maxY, geometry.paneBounds.maxY - 18, accuracy: 0.001)
    }

    func testBubbleStyleUsesTintedReadableTextDistinctFromPDFBlack() {
        let style = ReaderElfBubbleStyle.make(for: .skeptical)

        XCTAssertFalse(colorsMatch(style.textColor, ReaderElfBubbleStyle.pdfBodyReferenceColor))
    }

    func testBubbleStyleKeepsMainTextColorStableAcrossMoods() {
        let skepticalStyle = ReaderElfBubbleStyle.make(for: .skeptical)
        let alarmedStyle = ReaderElfBubbleStyle.make(for: .alarmed)

        XCTAssertTrue(colorsMatch(skepticalStyle.textColor, alarmedStyle.textColor))
        XCTAssertFalse(colorsMatch(skepticalStyle.accentColor, alarmedStyle.accentColor))
    }

    private func passage(pageIndex: Int, text: String) throws -> ReaderFocusPassageSnapshot {
        try XCTUnwrap(
            ReaderFocusPassageSnapshot(
                pageIndex: pageIndex,
                quotedText: text,
                rects: [ReaderAnnotationRect(rect: CGRect(x: 12, y: 20, width: 88, height: 14))],
                source: .viewport
            )
        )
    }

    private func line(text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> ReaderPassageLine {
        ReaderPassageLine(
            text: text,
            rect: ReaderAnnotationRect(rect: CGRect(x: x, y: y, width: width, height: height))
        )
    }

    private func comment(text: String) throws -> ReaderElfComment {
        ReaderElfComment(
            passage: try passage(pageIndex: 0, text: "A focused paragraph"),
            mood: .skeptical,
            text: text
        )
    }

    private func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        let left = lhs.usingColorSpace(.deviceRGB) ?? lhs
        let right = rhs.usingColorSpace(.deviceRGB) ?? rhs
        return abs(left.redComponent - right.redComponent) < 0.001
            && abs(left.greenComponent - right.greenComponent) < 0.001
            && abs(left.blueComponent - right.blueComponent) < 0.001
            && abs(left.alphaComponent - right.alphaComponent) < 0.001
    }
}
