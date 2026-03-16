import Foundation
import XCTest
@testable import PaperMaster

final class PaperAnnotationTests: XCTestCase {
    func testHighlightOverlayIdentityRoundTrips() {
        let annotationID = UUID()
        let identity = ReaderHighlightOverlayIdentity(annotationID: annotationID, rectIndex: 2)

        let decoded = ReaderHighlightOverlayIdentity(userName: identity.userName)

        XCTAssertEqual(decoded, identity)
    }

    func testHighlightOverlayIdentityRejectsForeignAndMalformedUserNames() {
        XCTAssertNil(ReaderHighlightOverlayIdentity(userName: nil))
        XCTAssertNil(ReaderHighlightOverlayIdentity(userName: "someoneelse:\(UUID().uuidString):0"))
        XCTAssertNil(ReaderHighlightOverlayIdentity(userName: "henrypaper:not-a-uuid:0"))
        XCTAssertNil(ReaderHighlightOverlayIdentity(userName: "henrypaper:\(UUID().uuidString):-1"))
        XCTAssertNil(ReaderHighlightOverlayIdentity(userName: "henrypaper:\(UUID().uuidString)"))
    }

    func testRectPayloadRoundTrips() {
        let rects = [
            CGRect(x: 12.34567, y: 90.12345, width: 42.55555, height: 10.77777),
            CGRect(x: 15.0, y: 70.0, width: 30.0, height: 9.0)
        ]

        let payload = ReaderRectPayloadCodec.encode(rects)
        let decoded = ReaderRectPayloadCodec.decode(payload)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0], ReaderAnnotationRect(rect: rects[0]))
        XCTAssertEqual(decoded[1], ReaderAnnotationRect(rect: rects[1]))
    }

    func testAnnotationMatchesSelectionWithNormalizedQuoteAndRects() throws {
        let paper = Paper(title: "Notes")
        let selection = ReaderSelectionSnapshot(
            pageIndex: 2,
            quotedText: "  A line\nwith spacing  ",
            rects: [CGRect(x: 8, y: 10, width: 80, height: 12)]
        )

        let annotation = PaperAnnotation(
            paper: paper,
            pageIndex: 2,
            quotedText: "A line with spacing",
            rectPayload: ReaderRectPayloadCodec.encode([CGRect(x: 8, y: 10, width: 80, height: 12)])
        )

        XCTAssertNotNil(selection)
        XCTAssertTrue(annotation.matches(try XCTUnwrap(selection)))
    }

    func testSidebarSortOrdersByPageThenCreationDate() {
        let paper = Paper(title: "Sort")
        let later = Date(timeIntervalSince1970: 2_000)
        let earlier = Date(timeIntervalSince1970: 1_000)

        let pageThree = PaperAnnotation(
            paper: paper,
            pageIndex: 3,
            quotedText: "Page three",
            rectPayload: "[]",
            createdAt: earlier,
            updatedAt: earlier
        )
        let pageOneLater = PaperAnnotation(
            paper: paper,
            pageIndex: 1,
            quotedText: "Later",
            rectPayload: "[]",
            createdAt: later,
            updatedAt: later
        )
        let pageOneEarlier = PaperAnnotation(
            paper: paper,
            pageIndex: 1,
            quotedText: "Earlier",
            rectPayload: "[]",
            createdAt: earlier,
            updatedAt: earlier
        )

        let sorted = [pageThree, pageOneLater, pageOneEarlier].sorted(by: PaperAnnotation.sidebarSort)

        XCTAssertEqual(sorted.map(\.quotedText), ["Earlier", "Later", "Page three"])
    }
}
