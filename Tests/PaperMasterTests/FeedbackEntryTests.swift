import Foundation
import SwiftData
import XCTest
@testable import PaperMasterShared

@MainActor
final class FeedbackEntryTests: XCTestCase {
    func testSubmissionRequiresIntendedAction() {
        XCTAssertThrowsError(
            try FeedbackSubmission(
                intendedAction: "   ",
                feedbackText: "The reader never opened."
            )
        ) { error in
            XCTAssertEqual(error as? FeedbackValidationError, .emptyIntendedAction)
        }
    }

    func testSubmissionRequiresFeedbackText() {
        XCTAssertThrowsError(
            try FeedbackSubmission(
                intendedAction: "Open the reader",
                feedbackText: "   "
            )
        ) { error in
            XCTAssertEqual(error as? FeedbackValidationError, .emptyFeedbackText)
        }
    }

    func testSaveFeedbackStoresSelectedPaperContext() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let paper = Paper(title: "Queued Paper", status: .reading)
        context.insert(paper)

        let services = makeServices()
        let submission = try FeedbackSubmission(
            intendedAction: "Open the reader",
            feedbackText: "The reader button did nothing."
        )

        let entry = try services.saveFeedback(
            snapshot: FeedbackSnapshot(screen: .queue, selectedPaper: paper),
            submission: submission,
            context: context
        )

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<FeedbackEntry>()).first)
        XCTAssertEqual(stored.id, entry.id)
        XCTAssertEqual(stored.screenRawValue, AppScreen.queue.rawValue)
        XCTAssertEqual(stored.screenTitle, AppScreen.queue.title)
        XCTAssertEqual(stored.selectedPaperID, paper.id)
        XCTAssertEqual(stored.selectedPaperTitle, "Queued Paper")
        XCTAssertEqual(stored.selectedPaperStatusRawValue, PaperStatus.reading.rawValue)
        XCTAssertEqual(stored.intendedAction, "Open the reader")
        XCTAssertEqual(stored.feedbackText, "The reader button did nothing.")
    }

    func testSaveFeedbackWithoutSelectedPaperLeavesPaperFieldsEmpty() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let services = makeServices()
        let submission = try FeedbackSubmission(
            intendedAction: "Review saved feedback",
            feedbackText: "The log is easy to scan."
        )

        try services.saveFeedback(
            snapshot: FeedbackSnapshot(screen: .settings, selectedPaper: nil),
            submission: submission,
            context: context
        )

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<FeedbackEntry>()).first)
        XCTAssertEqual(stored.screenRawValue, AppScreen.settings.rawValue)
        XCTAssertNil(stored.selectedPaperID)
        XCTAssertNil(stored.selectedPaperTitle)
        XCTAssertNil(stored.selectedPaperStatusRawValue)
    }

    func testCombinedExportTextIncludesContextAndFeedback() {
        let entries = [
            FeedbackEntry(
                createdAt: Date(timeIntervalSince1970: 1_762_340_400),
                screenRawValue: AppScreen.today.rawValue,
                screenTitle: AppScreen.today.title,
                selectedPaperID: UUID(),
                selectedPaperTitle: "Retrieval Agents",
                selectedPaperStatusRawValue: PaperStatus.scheduled.rawValue,
                intendedAction: "Reorder today's queue",
                feedbackText: "The queue should keep my manual order."
            ),
            FeedbackEntry(
                createdAt: Date(timeIntervalSince1970: 1_762_344_000),
                screenRawValue: AppScreen.settings.rawValue,
                screenTitle: AppScreen.settings.title,
                intendedAction: "Copy all feedback",
                feedbackText: "This export format is easy to paste."
            )
        ]

        let exportText = FeedbackEntry.combinedExportText(for: entries)

        XCTAssertTrue(exportText.contains("Screen: Today"))
        XCTAssertTrue(exportText.contains("Paper: Retrieval Agents (Scheduled)"))
        XCTAssertTrue(exportText.contains("Intended Action: Reorder today's queue"))
        XCTAssertTrue(exportText.contains("Feedback:\nThe queue should keep my manual order."))
        XCTAssertTrue(exportText.contains("Intended Action: Copy all feedback"))
        XCTAssertTrue(exportText.contains("This export format is easy to paste."))
    }

    private func makeServices() -> AppServices {
        AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            reminderService: ReminderService(center: FakeNotificationCenter())
        )
    }
}
