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
        let paper = Paper(title: "Editable Tags", status: .inbox)
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
    }
}
