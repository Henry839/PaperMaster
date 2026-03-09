import Foundation
import SwiftData
import XCTest
@testable import PaperReadingScheduler

@MainActor
final class AppServicesTests: XCTestCase {
    func testUpdateTagsReplacesPaperTags() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings()
        let paper = Paper(title: "Editable Tags", status: .inbox, autoTaggingStatusMessage: "AI auto-tagging failed: invalid response")
        let existingTag = Tag(name: "old-tag")
        paper.tags = [existingTag]
        context.insert(settings)
        context.insert(existingTag)
        context.insert(paper)

        let services = AppServices(
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

        services.updateTags(
            for: paper,
            tagString: "planning, agents",
            allPapers: [paper],
            settings: settings,
            context: context
        )

        XCTAssertEqual(Set(paper.tagNames), Set(["agents", "planning"]))
        XCTAssertNil(paper.autoTaggingStatusMessage)
    }

    func testDuplicateImportReturnsExistingPaperWithoutMutatingQueue() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(defaultImportBehavior: .scheduleImmediately)
        let existingPaper = Paper(
            title: "Queued Paper",
            sourceURL: URL(string: "https://arxiv.org/abs/2603.06028"),
            pdfURL: URL(string: "https://arxiv.org/pdf/2603.06028v1.pdf"),
            status: .scheduled,
            queuePosition: 0
        )
        context.insert(settings)
        context.insert(existingPaper)

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "Queued Paper",
                        authors: [],
                        abstractText: "",
                        sourceURL: URL(string: "https://arxiv.org/abs/2603.06028"),
                        pdfURL: URL(string: "https://arxiv.org/pdf/2603.06028v1.pdf")
                    )
                )
            ),
            reminderService: ReminderService(center: FakeNotificationCenter())
        )

        let returnedPaper = await services.importPaper(
            request: PaperCaptureRequest(sourceText: "https://arxiv.org/pdf/2603.06028v1.pdf"),
            settings: settings,
            currentPapers: [existingPaper],
            in: context
        )

        XCTAssertEqual(returnedPaper?.id, existingPaper.id)
        XCTAssertEqual(existingPaper.queuePosition, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Paper>()), 1)
    }

    func testCopyTextWritesToClipboardAndShowsNotice() {
        let clipboard = FakeTextClipboard()
        let services = AppServices(
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
            reminderService: ReminderService(center: FakeNotificationCenter()),
            textClipboard: clipboard
        )

        services.copyText("@article{test}", notice: "Copied BibTeX.")

        XCTAssertEqual(clipboard.lastCopiedString, "@article{test}")
        XCTAssertEqual(services.presentedNotice?.message, "Copied BibTeX.")
    }
}
