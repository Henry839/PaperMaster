import Foundation
import SwiftData
import XCTest
@testable import PaperReadingScheduler

@MainActor
final class PersistentStoreControllerTests: XCTestCase {
    func testCurrentStoreURLUsesAppSpecificLocation() throws {
        let rootDirectoryURL = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let controller = PersistentStoreController(applicationSupportDirectoryURL: rootDirectoryURL)

        XCTAssertEqual(
            controller.currentStoreURL.path,
            rootDirectoryURL
                .appendingPathComponent("HenryPaper", isDirectory: true)
                .appendingPathComponent("HenryPaper.store")
                .path
        )
        XCTAssertNotEqual(controller.currentStoreURL.path, controller.legacyStoreURL.path)
        XCTAssertFalse(controller.currentStoreURL.path.hasSuffix("/default.store"))
    }

    func testMakeLaunchSetupMigratesLegacyDefaultStoreIntoAppSpecificStore() throws {
        let rootDirectoryURL = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let controller = PersistentStoreController(
            applicationSupportDirectoryURL: rootDirectoryURL,
            now: { Date(timeIntervalSince1970: 1_741_520_800) }
        )
        try seedLegacyStore(at: controller.legacyStoreURL)

        let setup = controller.makeLaunchSetup()
        let context = ModelContext(setup.container)

        let papers = try context.fetch(FetchDescriptor<Paper>(sortBy: [SortDescriptor(\.queuePosition)]))
        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        let feedbackEntries = try context.fetch(FetchDescriptor<FeedbackEntry>())
        let tags = try context.fetch(FetchDescriptor<Tag>())

        XCTAssertEqual(setup.storeURL?.path, controller.currentStoreURL.path)
        XCTAssertEqual(setup.startupNoticeMessage, "Recovered 2 papers from the previous HenryPaper database.")
        XCTAssertNil(setup.startupErrorMessage)
        XCTAssertEqual(papers.map(\.title), ["Legacy Paper", "Another Legacy Paper"])
        XCTAssertEqual(Set(papers[0].tagNames), Set(["agents", "planning"]))
        XCTAssertEqual(Set(papers[1].tagNames), Set(["systems"]))
        XCTAssertEqual(tags.count, 3)
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(settings.first?.papersPerDay, 3)
        XCTAssertEqual(settings.first?.aiTaggingEnabled, true)
        XCTAssertEqual(feedbackEntries.count, 1)
        XCTAssertEqual(feedbackEntries.first?.screenTitle, AppScreen.queue.title)

        let backupDirectories = try FileManager.default.contentsOfDirectory(
            at: controller.backupRootDirectoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(backupDirectories.count, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: backupDirectories[0]
                    .appendingPathComponent(controller.legacyStoreURL.lastPathComponent)
                    .path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: controller.currentStoreURL.path))
    }

    private func seedLegacyStore(at storeURL: URL) throws {
        let schema = Schema(versionedSchema: PaperReadingSchedulerLegacySchemaV1.self)
        let configuration = ModelConfiguration(
            "LegacyHenryPaper",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)

        let settings = PaperReadingSchedulerLegacySchemaV1.UserSettings(
            papersPerDay: 3,
            dailyReminderTime: TestSupport.reminderDate(hour: 10, minute: 15),
            autoCachePDFs: true,
            defaultImportBehaviorRawValue: ImportBehavior.scheduleImmediately.rawValue,
            aiTaggingEnabled: true,
            aiTaggingBaseURLString: "https://api.openai.com/v1",
            aiTaggingModel: "gpt-4o-mini"
        )
        let first = PaperReadingSchedulerLegacySchemaV1.Paper(
            title: "Legacy Paper",
            authorsText: "Ada Lovelace, Grace Hopper",
            abstractText: "First legacy abstract.",
            venueKey: "neurips",
            venueName: "NeurIPS",
            doi: "10.1000/legacy-1",
            bibtex: "@article{legacy1}",
            sourceURLString: "https://example.com/legacy-1",
            pdfURLString: "https://example.com/legacy-1.pdf",
            statusRawValue: PaperStatus.scheduled.rawValue,
            queuePosition: 0,
            dateAdded: Date(timeIntervalSince1970: 1_700_000_000),
            notes: "Legacy notes",
            autoTaggingStatusMessage: "Legacy message",
            tags: [
                PaperReadingSchedulerLegacySchemaV1.Tag(name: "agents"),
                PaperReadingSchedulerLegacySchemaV1.Tag(name: "planning")
            ]
        )
        let second = PaperReadingSchedulerLegacySchemaV1.Paper(
            title: "Another Legacy Paper",
            authorsText: "Barbara Liskov",
            abstractText: "Second legacy abstract.",
            sourceURLString: "https://example.com/legacy-2",
            pdfURLString: "https://example.com/legacy-2.pdf",
            statusRawValue: PaperStatus.reading.rawValue,
            queuePosition: 1,
            dateAdded: Date(timeIntervalSince1970: 1_700_000_100),
            startedAt: Date(timeIntervalSince1970: 1_700_000_200),
            tags: [
                PaperReadingSchedulerLegacySchemaV1.Tag(name: "systems")
            ]
        )
        let feedbackEntry = PaperReadingSchedulerLegacySchemaV1.FeedbackEntry(
            createdAt: Date(timeIntervalSince1970: 1_700_000_300),
            screenRawValue: AppScreen.queue.rawValue,
            screenTitle: AppScreen.queue.title,
            selectedPaperID: second.id,
            selectedPaperTitle: second.title,
            selectedPaperStatusRawValue: second.statusRawValue,
            intendedAction: "Open the paper",
            feedbackText: "The old build reordered incorrectly."
        )

        context.insert(settings)
        context.insert(first)
        context.insert(second)
        context.insert(feedbackEntry)
        try context.save()
    }
}
