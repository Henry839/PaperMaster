import Foundation
import SwiftData

struct PersistentStoreSetup {
    let container: ModelContainer
    let startupNoticeMessage: String?
    let startupErrorMessage: String?
    let storeURL: URL?
}

struct PersistentStoreController {
    private let fileManager: FileManager
    let applicationSupportDirectoryURL: URL
    private let now: () -> Date

    init(
        fileManager: FileManager = .default,
        applicationSupportDirectoryURL: URL? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.now = now
    }

    var storeDirectoryURL: URL {
        applicationSupportDirectoryURL.appendingPathComponent("HenryPaper", isDirectory: true)
    }

    var currentStoreURL: URL {
        storeDirectoryURL.appendingPathComponent("HenryPaper.store")
    }

    var legacyStoreURL: URL {
        applicationSupportDirectoryURL.appendingPathComponent("default.store")
    }

    var backupRootDirectoryURL: URL {
        storeDirectoryURL.appendingPathComponent("StoreBackups", isDirectory: true)
    }

    func makeLaunchSetup() -> PersistentStoreSetup {
        do {
            return try makePersistentLaunchSetup()
        } catch {
            let container = try! ModelContainer(
                for: Schema(versionedSchema: PaperReadingSchedulerSchemaV2.self),
                migrationPlan: PaperReadingSchedulerMigrationPlan.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            return PersistentStoreSetup(
                container: container,
                startupNoticeMessage: nil,
                startupErrorMessage: "HenryPaper could not open its local library. The app started with a temporary empty session. \(error.localizedDescription)",
                storeURL: nil
            )
        }
    }

    private func makePersistentLaunchSetup() throws -> PersistentStoreSetup {
        try ensureDirectoryExists(at: storeDirectoryURL)

        if storeFamilyExists(at: currentStoreURL) {
            return PersistentStoreSetup(
                container: try makeCurrentContainer(at: currentStoreURL),
                startupNoticeMessage: nil,
                startupErrorMessage: nil,
                storeURL: currentStoreURL
            )
        }

        guard storeFamilyExists(at: legacyStoreURL) else {
            return PersistentStoreSetup(
                container: try makeCurrentContainer(at: currentStoreURL),
                startupNoticeMessage: nil,
                startupErrorMessage: nil,
                storeURL: currentStoreURL
            )
        }

        return try migrateLegacyDefaultStore()
    }

    private func migrateLegacyDefaultStore() throws -> PersistentStoreSetup {
        let backupDirectoryURL = try makeTimestampedDirectory(
            in: backupRootDirectoryURL,
            prefix: "LegacyDefaultStore"
        )
        let backedUpLegacyStoreURL = try copyStoreFamily(from: legacyStoreURL, toDirectory: backupDirectoryURL)

        do {
            let migrationSummary = try migrateLegacyStore(
                from: backedUpLegacyStoreURL,
                to: currentStoreURL
            )
            let startupNoticeMessage = migrationSummary.migratedPaperCount > 0
                ? "Recovered \(migrationSummary.migratedPaperCount) paper\(migrationSummary.migratedPaperCount == 1 ? "" : "s") from the previous HenryPaper database."
                : nil
            return PersistentStoreSetup(
                container: migrationSummary.container,
                startupNoticeMessage: startupNoticeMessage,
                startupErrorMessage: nil,
                storeURL: currentStoreURL
            )
        } catch {
            try? quarantineStoreFamilyIfExists(
                at: currentStoreURL,
                prefix: "FailedMigratedStore"
            )
            let container = try makeCurrentContainer(at: currentStoreURL)
            return PersistentStoreSetup(
                container: container,
                startupNoticeMessage: nil,
                startupErrorMessage: "HenryPaper could not migrate the previous library. The original database was preserved at \(backupDirectoryURL.path). A new empty library was created.",
                storeURL: currentStoreURL
            )
        }
    }

    private func migrateLegacyStore(from sourceStoreURL: URL, to destinationStoreURL: URL) throws -> MigrationSummary {
        let sourceContainer = try makeLegacyContainer(at: sourceStoreURL)
        let sourceContext = ModelContext(sourceContainer)

        let legacyPapers = try sourceContext.fetch(FetchDescriptor<PaperReadingSchedulerLegacySchemaV1.Paper>())
        let legacySettings = try sourceContext.fetch(FetchDescriptor<PaperReadingSchedulerLegacySchemaV1.UserSettings>())
        let legacyFeedbackEntries = try sourceContext.fetch(FetchDescriptor<PaperReadingSchedulerLegacySchemaV1.FeedbackEntry>())

        let destinationContainer = try makeCurrentContainer(at: destinationStoreURL)
        let destinationContext = ModelContext(destinationContainer)

        for legacySettingsEntry in legacySettings {
            destinationContext.insert(
                UserSettings(
                    id: legacySettingsEntry.id,
                    papersPerDay: legacySettingsEntry.papersPerDay,
                    dailyReminderTime: legacySettingsEntry.dailyReminderTime,
                    autoCachePDFs: legacySettingsEntry.autoCachePDFs,
                    defaultImportBehavior: ImportBehavior(rawValue: legacySettingsEntry.defaultImportBehaviorRawValue) ?? .scheduleImmediately,
                    aiTaggingEnabled: legacySettingsEntry.aiTaggingEnabled,
                    aiTaggingBaseURLString: legacySettingsEntry.aiTaggingBaseURLString,
                    aiTaggingModel: legacySettingsEntry.aiTaggingModel
                )
            )
        }

        for legacyPaper in legacyPapers {
            let paper = Paper(
                id: legacyPaper.id,
                title: legacyPaper.title,
                authors: legacyPaper.authors,
                abstractText: legacyPaper.abstractText,
                venueKey: legacyPaper.venueKey,
                venueName: legacyPaper.venueName,
                doi: legacyPaper.doi,
                bibtex: legacyPaper.bibtex,
                sourceURL: legacyPaper.sourceURL,
                pdfURL: legacyPaper.pdfURL,
                cachedPDFPath: legacyPaper.cachedPDFPath,
                status: PaperStatus(rawValue: legacyPaper.statusRawValue) ?? .inbox,
                queuePosition: legacyPaper.queuePosition,
                dateAdded: legacyPaper.dateAdded,
                dueDate: legacyPaper.dueDate,
                manualDueDateOverride: legacyPaper.manualDueDateOverride,
                startedAt: legacyPaper.startedAt,
                completedAt: legacyPaper.completedAt,
                notes: legacyPaper.notes,
                autoTaggingStatusMessage: legacyPaper.autoTaggingStatusMessage,
                tags: Tag.buildList(from: legacyPaper.tags.map(\.name))
            )
            destinationContext.insert(paper)
        }

        for legacyEntry in legacyFeedbackEntries {
            destinationContext.insert(
                FeedbackEntry(
                    id: legacyEntry.id,
                    createdAt: legacyEntry.createdAt,
                    screenRawValue: legacyEntry.screenRawValue,
                    screenTitle: legacyEntry.screenTitle,
                    selectedPaperID: legacyEntry.selectedPaperID,
                    selectedPaperTitle: legacyEntry.selectedPaperTitle,
                    selectedPaperStatusRawValue: legacyEntry.selectedPaperStatusRawValue,
                    intendedAction: legacyEntry.intendedAction,
                    feedbackText: legacyEntry.feedbackText
                )
            )
        }

        try destinationContext.save()
        return MigrationSummary(
            container: destinationContainer,
            migratedPaperCount: legacyPapers.count
        )
    }

    private func makeCurrentContainer(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PaperReadingSchedulerSchemaV2.self)
        let configuration = ModelConfiguration(
            "HenryPaper",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: PaperReadingSchedulerMigrationPlan.self,
            configurations: configuration
        )
    }

    private func makeLegacyContainer(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PaperReadingSchedulerLegacySchemaV1.self)
        let configuration = ModelConfiguration(
            "LegacyHenryPaper",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            configurations: configuration
        )
    }

    private func ensureDirectoryExists(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func makeTimestampedDirectory(in rootDirectoryURL: URL, prefix: String) throws -> URL {
        try ensureDirectoryExists(at: rootDirectoryURL)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let directoryURL = rootDirectoryURL.appendingPathComponent(
            "\(prefix)-\(sanitizedTimestamp(from: formatter.string(from: now())))",
            isDirectory: true
        )
        try ensureDirectoryExists(at: directoryURL)
        return directoryURL
    }

    private func copyStoreFamily(from baseStoreURL: URL, toDirectory directoryURL: URL) throws -> URL {
        let sourceURLs = existingStoreFamilyURLs(for: baseStoreURL)
        guard sourceURLs.isEmpty == false else {
            throw PersistentStoreControllerError.storeFamilyMissing(baseStoreURL.path)
        }

        try ensureDirectoryExists(at: directoryURL)
        for sourceURL in sourceURLs {
            let destinationURL = directoryURL.appendingPathComponent(sourceURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        return directoryURL.appendingPathComponent(baseStoreURL.lastPathComponent)
    }

    private func quarantineStoreFamilyIfExists(at baseStoreURL: URL, prefix: String) throws {
        let existingURLs = existingStoreFamilyURLs(for: baseStoreURL)
        guard existingURLs.isEmpty == false else { return }

        let quarantineDirectoryURL = try makeTimestampedDirectory(in: backupRootDirectoryURL, prefix: prefix)
        for existingURL in existingURLs {
            let destinationURL = quarantineDirectoryURL.appendingPathComponent(existingURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: existingURL, to: destinationURL)
        }
    }

    private func existingStoreFamilyURLs(for baseStoreURL: URL) -> [URL] {
        ["", "-shm", "-wal"]
            .map { URL(fileURLWithPath: baseStoreURL.path + $0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func storeFamilyExists(at baseStoreURL: URL) -> Bool {
        existingStoreFamilyURLs(for: baseStoreURL).isEmpty == false
    }

    private func sanitizedTimestamp(from value: String) -> String {
        value.replacingOccurrences(of: ":", with: "-")
    }
}

private struct MigrationSummary {
    let container: ModelContainer
    let migratedPaperCount: Int
}

private enum PersistentStoreControllerError: LocalizedError {
    case storeFamilyMissing(String)

    var errorDescription: String? {
        switch self {
        case let .storeFamilyMissing(path):
            return "No SwiftData store files were found at \(path)."
        }
    }
}

enum PaperReadingSchedulerLegacySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Paper.self, Tag.self, UserSettings.self, FeedbackEntry.self]
    }

    @Model
    final class Paper {
        @Attribute(.unique) var id: UUID
        var title: String
        var authorsText: String
        var abstractText: String
        var venueKey: String?
        var venueName: String?
        var doi: String?
        var bibtex: String?
        var sourceURLString: String?
        var pdfURLString: String?
        var cachedPDFPath: String?
        var statusRawValue: String
        var queuePosition: Int
        var dateAdded: Date
        var dueDate: Date?
        var manualDueDateOverride: Date?
        var startedAt: Date?
        var completedAt: Date?
        var notes: String
        var autoTaggingStatusMessage: String?
        var tags: [Tag]

        init(
            id: UUID = UUID(),
            title: String,
            authorsText: String = "",
            abstractText: String = "",
            venueKey: String? = nil,
            venueName: String? = nil,
            doi: String? = nil,
            bibtex: String? = nil,
            sourceURLString: String? = nil,
            pdfURLString: String? = nil,
            cachedPDFPath: String? = nil,
            statusRawValue: String = PaperStatus.inbox.rawValue,
            queuePosition: Int = 0,
            dateAdded: Date = .now,
            dueDate: Date? = nil,
            manualDueDateOverride: Date? = nil,
            startedAt: Date? = nil,
            completedAt: Date? = nil,
            notes: String = "",
            autoTaggingStatusMessage: String? = nil,
            tags: [Tag] = []
        ) {
            self.id = id
            self.title = title
            self.authorsText = authorsText
            self.abstractText = abstractText
            self.venueKey = venueKey
            self.venueName = venueName
            self.doi = doi
            self.bibtex = bibtex
            self.sourceURLString = sourceURLString
            self.pdfURLString = pdfURLString
            self.cachedPDFPath = cachedPDFPath
            self.statusRawValue = statusRawValue
            self.queuePosition = queuePosition
            self.dateAdded = dateAdded
            self.dueDate = dueDate
            self.manualDueDateOverride = manualDueDateOverride
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.notes = notes
            self.autoTaggingStatusMessage = autoTaggingStatusMessage
            self.tags = tags
        }

        var authors: [String] {
            authorsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        var sourceURL: URL? {
            sourceURLString.flatMap(URL.init(string:))
        }

        var pdfURL: URL? {
            pdfURLString.flatMap(URL.init(string:))
        }
    }

    @Model
    final class Tag {
        @Attribute(.unique) var name: String

        init(name: String) {
            self.name = Tag.normalize(name)
        }

        static func normalize(_ value: String) -> String {
            value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }
    }

    @Model
    final class UserSettings {
        @Attribute(.unique) var id: UUID
        var papersPerDay: Int
        var dailyReminderTime: Date
        var autoCachePDFs: Bool
        var defaultImportBehaviorRawValue: String
        var aiTaggingEnabled: Bool
        var aiTaggingBaseURLString: String
        var aiTaggingModel: String

        init(
            id: UUID = UUID(),
            papersPerDay: Int = 1,
            dailyReminderTime: Date = Date(),
            autoCachePDFs: Bool = false,
            defaultImportBehaviorRawValue: String = ImportBehavior.scheduleImmediately.rawValue,
            aiTaggingEnabled: Bool = false,
            aiTaggingBaseURLString: String = "https://api.openai.com/v1",
            aiTaggingModel: String = "gpt-4o-mini"
        ) {
            self.id = id
            self.papersPerDay = papersPerDay
            self.dailyReminderTime = dailyReminderTime
            self.autoCachePDFs = autoCachePDFs
            self.defaultImportBehaviorRawValue = defaultImportBehaviorRawValue
            self.aiTaggingEnabled = aiTaggingEnabled
            self.aiTaggingBaseURLString = aiTaggingBaseURLString
            self.aiTaggingModel = aiTaggingModel
        }
    }

    @Model
    final class FeedbackEntry {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var screenRawValue: String
        var screenTitle: String
        var selectedPaperID: UUID?
        var selectedPaperTitle: String?
        var selectedPaperStatusRawValue: String?
        var intendedAction: String
        var feedbackText: String

        init(
            id: UUID = UUID(),
            createdAt: Date = .now,
            screenRawValue: String,
            screenTitle: String,
            selectedPaperID: UUID? = nil,
            selectedPaperTitle: String? = nil,
            selectedPaperStatusRawValue: String? = nil,
            intendedAction: String,
            feedbackText: String
        ) {
            self.id = id
            self.createdAt = createdAt
            self.screenRawValue = screenRawValue
            self.screenTitle = screenTitle
            self.selectedPaperID = selectedPaperID
            self.selectedPaperTitle = selectedPaperTitle
            self.selectedPaperStatusRawValue = selectedPaperStatusRawValue
            self.intendedAction = intendedAction
            self.feedbackText = feedbackText
        }
    }
}

enum PaperReadingSchedulerSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Paper.self, Tag.self, UserSettings.self, FeedbackEntry.self]
    }
}

enum PaperReadingSchedulerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PaperReadingSchedulerLegacySchemaV1.self, PaperReadingSchedulerSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: PaperReadingSchedulerLegacySchemaV1.self,
                toVersion: PaperReadingSchedulerSchemaV2.self
            )
        ]
    }
}
