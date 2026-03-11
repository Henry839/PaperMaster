import CoreGraphics
import Foundation
import XCTest
@testable import PaperMaster

final class ReaderAskAITests: XCTestCase {
    func testSessionCapturePrefillsDefaultQuestion() throws {
        var session = ReaderAskAISessionState()

        session.capture(selection: try selection(pageIndex: 0, text: "A useful quote"))

        XCTAssertEqual(session.draft?.question, ReaderAskAIDraft.defaultQuestion)
        XCTAssertEqual(session.draft?.selection.pageNumber, 1)
    }

    func testSessionFinishRequestPrependsNewestExchange() throws {
        var session = ReaderAskAISessionState()

        session.capture(selection: try selection(pageIndex: 0, text: "First quote"))
        let firstDraft = try XCTUnwrap(session.beginRequest())
        session.finishRequest(
            with: firstDraft,
            answer: "First answer",
            askedAt: Date(timeIntervalSince1970: 10)
        )

        session.capture(selection: try selection(pageIndex: 1, text: "Second quote"))
        session.updateQuestion("What changed?")
        let secondDraft = try XCTUnwrap(session.beginRequest())
        session.finishRequest(
            with: secondDraft,
            answer: "Second answer",
            askedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(session.exchanges.map(\.answer), ["Second answer", "First answer"])
        XCTAssertEqual(session.exchanges.map(\.pageNumber), [2, 1])
    }

    func testSessionResetClearsDraftHistoryAndLoadingState() throws {
        var session = ReaderAskAISessionState()

        session.capture(selection: try selection(pageIndex: 2, text: "Reset me"))
        _ = session.beginRequest()
        session.finishRequest(
            with: try XCTUnwrap(session.draft),
            answer: "Done",
            askedAt: Date(timeIntervalSince1970: 30)
        )

        session.reset()

        XCTAssertNil(session.draft)
        XCTAssertTrue(session.exchanges.isEmpty)
        XCTAssertFalse(session.isAwaitingResponse)
    }

    func testDocumentContextNormalizesWhitespaceAndTruncates() {
        let context = ReaderAskAIDocumentContext.make(
            from: "  A line\nwith   extra\tspacing and more words  ",
            limit: 20
        )

        XCTAssertTrue(context.documentWasTruncated)
        XCTAssertEqual(context.documentText, "A line with extra sp")
    }

    private func selection(pageIndex: Int, text: String) throws -> ReaderSelectionSnapshot {
        try XCTUnwrap(
            ReaderSelectionSnapshot(
                pageIndex: pageIndex,
                quotedText: text,
                rects: [CGRect(x: 8, y: 12, width: 80, height: 12)]
            )
        )
    }
}
