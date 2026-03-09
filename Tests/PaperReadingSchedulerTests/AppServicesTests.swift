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

    func testMoveToEarlierQueueIndexReordersQueueAndClearsMovedOverride() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(papersPerDay: 1)
        let first = Paper(title: "First", status: .scheduled, queuePosition: 0)
        let moved = Paper(
            title: "Moved",
            status: .scheduled,
            queuePosition: 1,
            manualDueDateOverride: TestSupport.reminderDate(hour: 13, minute: 0)
        )
        let third = Paper(title: "Third", status: .reading, queuePosition: 2)
        let inbox = Paper(title: "Inbox", status: .inbox, queuePosition: 99)

        context.insert(settings)
        context.insert(first)
        context.insert(moved)
        context.insert(third)
        context.insert(inbox)

        let services = makeServices()

        services.move(
            paper: moved,
            toQueueIndex: 0,
            allPapers: [first, moved, third, inbox],
            settings: settings,
            context: context
        )

        let queue = [first, moved, third].sorted { $0.queuePosition < $1.queuePosition }
        XCTAssertEqual(queue.map(\.id), [moved.id, first.id, third.id])
        XCTAssertEqual(queue.map(\.queuePosition), [0, 1, 2])
        XCTAssertNil(moved.manualDueDateOverride)
    }

    func testMoveToLaterQueueIndexRewritesQueuePositionsContiguously() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(papersPerDay: 1)
        let first = Paper(title: "First", status: .scheduled, queuePosition: 0)
        let second = Paper(title: "Second", status: .scheduled, queuePosition: 1)
        let third = Paper(title: "Third", status: .scheduled, queuePosition: 2)
        let fourth = Paper(title: "Fourth", status: .reading, queuePosition: 3)

        context.insert(settings)
        context.insert(first)
        context.insert(second)
        context.insert(third)
        context.insert(fourth)

        let services = makeServices()

        services.move(
            paper: first,
            toQueueIndex: 2,
            allPapers: [first, second, third, fourth],
            settings: settings,
            context: context
        )

        let queue = [first, second, third, fourth].sorted { $0.queuePosition < $1.queuePosition }
        XCTAssertEqual(queue.map(\.id), [second.id, third.id, first.id, fourth.id])
        XCTAssertEqual(queue.map(\.queuePosition), [0, 1, 2, 3])
    }

    func testMoveToQueueIndexAtBoundsIsNoOp() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(papersPerDay: 1)
        let topOverride = TestSupport.reminderDate(hour: 10, minute: 0)
        let bottomOverride = TestSupport.reminderDate(hour: 16, minute: 0)
        let first = Paper(
            title: "First",
            status: .scheduled,
            queuePosition: 0,
            manualDueDateOverride: topOverride
        )
        let second = Paper(title: "Second", status: .scheduled, queuePosition: 1)
        let third = Paper(
            title: "Third",
            status: .reading,
            queuePosition: 2,
            manualDueDateOverride: bottomOverride
        )

        context.insert(settings)
        context.insert(first)
        context.insert(second)
        context.insert(third)

        let services = makeServices()

        services.move(
            paper: first,
            toQueueIndex: -5,
            allPapers: [first, second, third],
            settings: settings,
            context: context
        )
        services.move(
            paper: third,
            toQueueIndex: 99,
            allPapers: [first, second, third],
            settings: settings,
            context: context
        )

        let queue = [first, second, third].sorted { $0.queuePosition < $1.queuePosition }
        XCTAssertEqual(queue.map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(queue.map(\.queuePosition), [0, 1, 2])
        XCTAssertEqual(first.manualDueDateOverride, topOverride)
        XCTAssertEqual(third.manualDueDateOverride, bottomOverride)
    }

    func testQueueReorderTagEditAndDeleteRemainStableWithOverlappingTagNames() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(papersPerDay: 1)
        let first = Paper(
            title: "First",
            status: .scheduled,
            queuePosition: 0,
            tags: Tag.buildList(from: ["agents"])
        )
        let second = Paper(
            title: "Second",
            status: .scheduled,
            queuePosition: 1,
            tags: Tag.buildList(from: ["agents"])
        )

        context.insert(settings)
        context.insert(first)
        context.insert(second)
        try context.save()

        let services = makeServices()

        services.move(
            paper: second,
            toQueueIndex: 0,
            allPapers: [first, second],
            settings: settings,
            context: context
        )
        services.updateTags(
            for: first,
            tagString: "agents, planning",
            allPapers: [first, second],
            settings: settings,
            context: context
        )
        services.delete(
            paper: second,
            allPapers: [first, second],
            settings: settings,
            context: context
        )

        let storedPapers = try context.fetch(FetchDescriptor<Paper>())
        let storedTags = try context.fetch(FetchDescriptor<Tag>())

        XCTAssertEqual(storedPapers.map(\.id), [first.id])
        XCTAssertEqual(first.queuePosition, 0)
        XCTAssertEqual(Set(first.tagNames), Set(["agents", "planning"]))
        XCTAssertEqual(storedTags.count, 2)
        XCTAssertEqual(Set(storedTags.map(\.name)), Set(["agents", "planning"]))
        XCTAssertTrue(storedTags.allSatisfy { $0.paper?.id == first.id })
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
