import PDFKit
import XCTest
@testable import PaperMasterShared

@MainActor
final class ReaderCompanionPassageExtractionTests: XCTestCase {
    func testViewportPassageExtractionReturnsStablePageAnchors() throws {
        let directoryURL = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("viewport.pdf")
        try TestSupport.makePDF(
            at: fileURL,
            title: "Viewport Reader Test",
            body: """
            Intro paragraph line one with framing.
            Intro paragraph line two with context.
            Intro paragraph line three with setup.

            Middle paragraph line one questions the baseline choice.
            Middle paragraph line two points to the narrow evaluation.
            Middle paragraph line three hints at overclaiming.

            Final paragraph line one wraps up the discussion.
            Final paragraph line two closes the page.
            """
        )

        let document = try XCTUnwrap(PDFDocument(url: fileURL))
        let page = try XCTUnwrap(document.page(at: 0))
        let centerPoint = CGPoint(x: page.bounds(for: .cropBox).midX, y: page.bounds(for: .cropBox).midY)

        let passage = try XCTUnwrap(
            ReaderFocusPassageExtractor.passage(
                on: page,
                pageIndex: 0,
                around: centerPoint
            )
        )

        XCTAssertEqual(passage.pageIndex, 0)
        XCTAssertEqual(passage.source, .viewport)
        XCTAssertFalse(passage.quotedText.isEmpty)
        XCTAssertGreaterThanOrEqual(passage.rects.count, 1)
        XCTAssertTrue(
            passage.quotedText.contains("Middle paragraph")
                || passage.quotedText.contains("baseline")
                || passage.quotedText.contains("evaluation")
        )
    }

    func testOverlayGeometryCaptureConvertsPassageIntoPaneCoordinates() throws {
        let directoryURL = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("overlay-geometry.pdf")
        try TestSupport.makePDF(
            at: fileURL,
            title: "Overlay Geometry Test",
            body: """
            Opening paragraph line one.
            Opening paragraph line two.

            Anchor paragraph line one highlights the limitation.
            Anchor paragraph line two keeps the paragraph centered.
            Anchor paragraph line three gives enough text for extraction.

            Closing paragraph line one.
            Closing paragraph line two.
            """
        )

        let document = try XCTUnwrap(PDFDocument(url: fileURL))
        let page = try XCTUnwrap(document.page(at: 0))
        let centerPoint = CGPoint(x: page.bounds(for: .cropBox).midX, y: page.bounds(for: .cropBox).midY)
        let passage = try XCTUnwrap(
            ReaderFocusPassageExtractor.passage(
                on: page,
                pageIndex: 0,
                around: centerPoint
            )
        )

        let pdfView = PDFView(frame: CGRect(x: 0, y: 0, width: 820, height: 940))
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.autoScales = true
        pdfView.document = document
        pdfView.layoutSubtreeIfNeeded()

        let geometry = ReaderElfGeometrySnapshot.capture(for: passage, in: pdfView)
        let pageFrame = try XCTUnwrap(geometry.pageFrame)
        let anchorFrame = try XCTUnwrap(geometry.anchorFrame)

        XCTAssertEqual(geometry.passageKey, passage.normalizedKey)
        XCTAssertEqual(geometry.paneBounds.size, pdfView.bounds.size)
        XCTAssertEqual(geometry.passageLineFrames.count, passage.rects.count)
        XCTAssertTrue(pageFrame.contains(CGPoint(x: anchorFrame.midX, y: anchorFrame.midY)))
        XCTAssertGreaterThanOrEqual(passage.rects.count, 2)
        XCTAssertGreaterThan(anchorFrame.height, passage.rects[0].height)
        XCTAssertGreaterThan(anchorFrame.width, 0)
        XCTAssertGreaterThan(anchorFrame.height, 0)
        XCTAssertEqual(
            geometry.passageLineFrames.reduce(CGRect.null) { partialResult, rect in
                partialResult.isNull ? rect : partialResult.union(rect)
            }.standardized,
            anchorFrame
        )
    }
}
