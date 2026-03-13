import Foundation
import SQLite3
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
        applicationSupportDirectoryURL.appendingPathComponent("PaperMaster", isDirectory: true)
    }

    var currentStoreURL: URL {
        storeDirectoryURL.appendingPathComponent("PaperMaster.store")
    }

    var previousAppStoreDirectoryURL: URL {
        applicationSupportDirectoryURL.appendingPathComponent("HenryPaper", isDirectory: true)
    }

    var previousAppStoreURL: URL {
        previousAppStoreDirectoryURL.appendingPathComponent("HenryPaper.store")
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
                for: Schema(versionedSchema: PaperMasterSchemaV5.self),
                migrationPlan: PaperMasterMigrationPlan.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            return PersistentStoreSetup(
                container: container,
                startupNoticeMessage: nil,
                startupErrorMessage: "PaperMaster could not open its local library. The app started with a temporary empty session. \(error.localizedDescription)",
                storeURL: nil
            )
        }
    }

    private func makePersistentLaunchSetup() throws -> PersistentStoreSetup {
        try ensureDirectoryExists(at: storeDirectoryURL)

        if storeFamilyExists(at: currentStoreURL) {
            do {
                return PersistentStoreSetup(
                    container: try makeCurrentContainer(at: currentStoreURL),
                    startupNoticeMessage: nil,
                    startupErrorMessage: nil,
                    storeURL: currentStoreURL
                )
            } catch {
                return try recoverCurrentStore(afterOpenError: error)
            }
        }

        if storeFamilyExists(at: previousAppStoreURL) {
            return try migratePreviousAppStore()
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

    private func migratePreviousAppStore() throws -> PersistentStoreSetup {
        let backupDirectoryURL = try makeTimestampedDirectory(
            in: backupRootDirectoryURL,
            prefix: "PreviousAppStore"
        )
        let backedUpStoreURL = try copyStoreFamily(from: previousAppStoreURL, toDirectory: backupDirectoryURL)

        do {
            let migrationSummary = try migrateCurrentSQLiteStore(
                from: backedUpStoreURL,
                to: currentStoreURL
            )
            let startupNoticeMessage = migrationSummary.migratedPaperCount > 0
                ? "Recovered \(migrationSummary.migratedPaperCount) paper\(migrationSummary.migratedPaperCount == 1 ? "" : "s") from your previous HenryPaper library."
                : "Recovered your previous HenryPaper library."
            return PersistentStoreSetup(
                container: migrationSummary.container,
                startupNoticeMessage: startupNoticeMessage,
                startupErrorMessage: nil,
                storeURL: currentStoreURL
            )
        } catch {
            try? quarantineStoreFamilyIfExists(
                at: currentStoreURL,
                prefix: "FailedPreviousAppMigration"
            )
            let container = try makeCurrentContainer(at: currentStoreURL)
            return PersistentStoreSetup(
                container: container,
                startupNoticeMessage: nil,
                startupErrorMessage: "PaperMaster could not migrate the previous HenryPaper library. The original database was preserved at \(backupDirectoryURL.path). A new empty library was created.",
                storeURL: currentStoreURL
            )
        }
    }

    private func recoverCurrentStore(afterOpenError openError: Error) throws -> PersistentStoreSetup {
        let backupDirectoryURL = try makeTimestampedDirectory(
            in: backupRootDirectoryURL,
            prefix: "CurrentStoreRecovery"
        )
        let backedUpCurrentStoreURL = try copyStoreFamily(from: currentStoreURL, toDirectory: backupDirectoryURL)

        do {
            try removeStoreFamilyIfExists(at: currentStoreURL)
            let migrationSummary = try migrateCurrentSQLiteStore(
                from: backedUpCurrentStoreURL,
                to: currentStoreURL
            )
            let startupNoticeMessage = migrationSummary.migratedPaperCount > 0
                ? "Recovered \(migrationSummary.migratedPaperCount) paper\(migrationSummary.migratedPaperCount == 1 ? "" : "s") from your previous PaperMaster library."
                : "Recovered your previous PaperMaster library."
            return PersistentStoreSetup(
                container: migrationSummary.container,
                startupNoticeMessage: startupNoticeMessage,
                startupErrorMessage: nil,
                storeURL: currentStoreURL
            )
        } catch {
            try? removeStoreFamilyIfExists(at: currentStoreURL)
            let container = try makeCurrentContainer(at: currentStoreURL)
            return PersistentStoreSetup(
                container: container,
                startupNoticeMessage: nil,
                startupErrorMessage: "PaperMaster could not open the previous local library. A backup was preserved at \(backupDirectoryURL.path). A new empty library was created. \(openError.localizedDescription)",
                storeURL: currentStoreURL
            )
        }
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
                startupErrorMessage: "PaperMaster could not migrate the previous HenryPaper database. The original database was preserved at \(backupDirectoryURL.path). A new empty library was created.",
                storeURL: currentStoreURL
            )
        }
    }

    private func migrateLegacyStore(from sourceStoreURL: URL, to destinationStoreURL: URL) throws -> MigrationSummary {
        let sourceContainer = try makeLegacyContainer(at: sourceStoreURL)
        let sourceContext = ModelContext(sourceContainer)

        let legacyPapers = try sourceContext.fetch(FetchDescriptor<PaperMasterLegacySchemaV1.Paper>())
        let legacySettings = try sourceContext.fetch(FetchDescriptor<PaperMasterLegacySchemaV1.UserSettings>())
        let legacyFeedbackEntries = try sourceContext.fetch(FetchDescriptor<PaperMasterLegacySchemaV1.FeedbackEntry>())

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
                    paperStorageMode: .defaultLocal,
                    customPaperStoragePath: "",
                    remotePaperStorageHost: "",
                    remotePaperStoragePort: 22,
                    remotePaperStorageUsername: "",
                    remotePaperStorageDirectory: "",
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
                managedPDFLocalPath: nil,
                managedPDFRemoteURLString: nil,
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

    private func migrateCurrentSQLiteStore(from sourceStoreURL: URL, to destinationStoreURL: URL) throws -> MigrationSummary {
        let snapshot = try CurrentStoreSQLiteReader.read(from: sourceStoreURL)
        let destinationContainer = try makeCurrentContainer(at: destinationStoreURL)
        let destinationContext = ModelContext(destinationContainer)
        let annotationsByPaperRowID = Dictionary(grouping: snapshot.annotations, by: \.paperRowID)
        var destinationPapersByRowID: [Int64: Paper] = [:]

        for settingsEntry in snapshot.settings {
            destinationContext.insert(
                UserSettings(
                    id: settingsEntry.id,
                    papersPerDay: settingsEntry.papersPerDay,
                    dailyReminderTime: settingsEntry.dailyReminderTime,
                    autoCachePDFs: settingsEntry.autoCachePDFs,
                    defaultImportBehavior: ImportBehavior(rawValue: settingsEntry.defaultImportBehaviorRawValue) ?? .scheduleImmediately,
                    paperStorageMode: .defaultLocal,
                    customPaperStoragePath: "",
                    remotePaperStorageHost: "",
                    remotePaperStoragePort: 22,
                    remotePaperStorageUsername: "",
                    remotePaperStorageDirectory: "",
                    aiTaggingEnabled: settingsEntry.aiTaggingEnabled,
                    aiTaggingBaseURLString: settingsEntry.aiTaggingBaseURLString,
                    aiTaggingModel: settingsEntry.aiTaggingModel
                )
            )
        }

        for paperEntry in snapshot.papers {
            let paper = Paper(
                id: paperEntry.id,
                title: paperEntry.title,
                authors: paperEntry.authors,
                abstractText: paperEntry.abstractText,
                venueKey: paperEntry.venueKey,
                venueName: paperEntry.venueName,
                doi: paperEntry.doi,
                bibtex: paperEntry.bibtex,
                sourceURL: paperEntry.sourceURL,
                pdfURL: paperEntry.pdfURL,
                cachedPDFPath: paperEntry.cachedPDFPath,
                managedPDFLocalPath: nil,
                managedPDFRemoteURLString: nil,
                status: PaperStatus(rawValue: paperEntry.statusRawValue) ?? .inbox,
                queuePosition: paperEntry.queuePosition,
                dateAdded: paperEntry.dateAdded,
                dueDate: paperEntry.dueDate,
                manualDueDateOverride: paperEntry.manualDueDateOverride,
                startedAt: paperEntry.startedAt,
                completedAt: paperEntry.completedAt,
                notes: paperEntry.notes,
                autoTaggingStatusMessage: paperEntry.autoTaggingStatusMessage,
                tags: Tag.buildList(from: paperEntry.tagNames)
            )
            destinationContext.insert(paper)
            destinationPapersByRowID[paperEntry.rowID] = paper

            for annotationEntry in annotationsByPaperRowID[paperEntry.rowID] ?? [] {
                destinationContext.insert(
                    PaperAnnotation(
                        id: annotationEntry.id,
                        paper: paper,
                        pageIndex: annotationEntry.pageIndex,
                        quotedText: annotationEntry.quotedText,
                        noteText: annotationEntry.noteText,
                        color: ReaderHighlightColor(rawValue: annotationEntry.colorRawValue) ?? .yellow,
                        rectPayload: annotationEntry.rectPayload,
                        createdAt: annotationEntry.createdAt,
                        updatedAt: annotationEntry.updatedAt
                    )
                )
            }
        }

        for cardEntry in snapshot.paperCards {
            guard let paper = destinationPapersByRowID[cardEntry.paperRowID] else { continue }
            let card = PaperCard(
                id: cardEntry.id,
                paper: paper,
                createdAt: cardEntry.createdAt,
                updatedAt: cardEntry.updatedAt,
                formatVersion: cardEntry.formatVersion,
                headline: cardEntry.headline,
                venueLine: cardEntry.venueLine,
                citationLine: cardEntry.citationLine,
                keywords: (try? JSONDecoder().decode([String].self, from: Data(cardEntry.keywordsPayload.utf8))) ?? [],
                sections: (try? JSONDecoder().decode([PaperCardSection].self, from: Data(cardEntry.sectionsPayload.utf8))) ?? [],
                htmlContent: cardEntry.htmlContent,
                htmlExportPath: cardEntry.htmlExportPath
            )
            destinationContext.insert(card)
            paper.paperCard = card
        }

        for feedbackEntry in snapshot.feedbackEntries {
            destinationContext.insert(
                FeedbackEntry(
                    id: feedbackEntry.id,
                    createdAt: feedbackEntry.createdAt,
                    screenRawValue: feedbackEntry.screenRawValue,
                    screenTitle: feedbackEntry.screenTitle,
                    selectedPaperID: feedbackEntry.selectedPaperID,
                    selectedPaperTitle: feedbackEntry.selectedPaperTitle,
                    selectedPaperStatusRawValue: feedbackEntry.selectedPaperStatusRawValue,
                    intendedAction: feedbackEntry.intendedAction,
                    feedbackText: feedbackEntry.feedbackText
                )
            )
        }

        try destinationContext.save()
        return MigrationSummary(
            container: destinationContainer,
            migratedPaperCount: snapshot.papers.count
        )
    }

    private func makeCurrentContainer(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PaperMasterSchemaV5.self)
        let configuration = ModelConfiguration(
            "PaperMaster",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: PaperMasterMigrationPlan.self,
            configurations: configuration
        )
    }

    private func makeLegacyContainer(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PaperMasterLegacySchemaV1.self)
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

    private func removeStoreFamilyIfExists(at baseStoreURL: URL) throws {
        for existingURL in existingStoreFamilyURLs(for: baseStoreURL) {
            try fileManager.removeItem(at: existingURL)
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
    case sqliteOpenFailed(String)
    case sqlitePrepareFailed(String)
    case invalidUUIDData
    case unexpectedSQLiteSchema(String)

    var errorDescription: String? {
        switch self {
        case let .storeFamilyMissing(path):
            return "No SwiftData store files were found at \(path)."
        case let .sqliteOpenFailed(path):
            return "PaperMaster could not read the previous HenryPaper database at \(path)."
        case let .sqlitePrepareFailed(message):
            return "PaperMaster could not read the previous HenryPaper database schema. \(message)"
        case .invalidUUIDData:
            return "PaperMaster could not read an identifier from the previous HenryPaper database."
        case let .unexpectedSQLiteSchema(tableName):
            return "PaperMaster could not read the previous HenryPaper database table \(tableName)."
        }
    }
}

private struct CurrentStoreSnapshot {
    let papers: [CurrentStorePaperRecord]
    let paperCards: [CurrentStorePaperCardRecord]
    let annotations: [CurrentStoreAnnotationRecord]
    let settings: [CurrentStoreSettingsRecord]
    let feedbackEntries: [CurrentStoreFeedbackEntryRecord]
}

private struct CurrentStorePaperRecord {
    let rowID: Int64
    let id: UUID
    let title: String
    let authors: [String]
    let abstractText: String
    let venueKey: String?
    let venueName: String?
    let doi: String?
    let bibtex: String?
    let sourceURL: URL?
    let pdfURL: URL?
    let cachedPDFPath: String?
    let statusRawValue: String
    let queuePosition: Int
    let dateAdded: Date
    let dueDate: Date?
    let manualDueDateOverride: Date?
    let startedAt: Date?
    let completedAt: Date?
    let notes: String
    let autoTaggingStatusMessage: String?
    var tagNames: [String]
}

private struct CurrentStoreAnnotationRecord {
    let id: UUID
    let paperRowID: Int64
    let pageIndex: Int
    let quotedText: String
    let noteText: String
    let colorRawValue: String
    let rectPayload: String
    let createdAt: Date
    let updatedAt: Date
}

private struct CurrentStorePaperCardRecord {
    let id: UUID
    let paperRowID: Int64
    let createdAt: Date
    let updatedAt: Date
    let formatVersion: Int
    let headline: String
    let venueLine: String
    let citationLine: String
    let keywordsPayload: String
    let sectionsPayload: String
    let htmlContent: String
    let htmlExportPath: String?
}

private struct CurrentStoreSettingsRecord {
    let id: UUID
    let papersPerDay: Int
    let dailyReminderTime: Date
    let autoCachePDFs: Bool
    let defaultImportBehaviorRawValue: String
    let aiTaggingEnabled: Bool
    let aiTaggingBaseURLString: String
    let aiTaggingModel: String
}

private struct CurrentStoreFeedbackEntryRecord {
    let id: UUID
    let createdAt: Date
    let screenRawValue: String
    let screenTitle: String
    let selectedPaperID: UUID?
    let selectedPaperTitle: String?
    let selectedPaperStatusRawValue: String?
    let intendedAction: String
    let feedbackText: String
}

private enum CurrentStoreSQLiteReader {
    static func read(from storeURL: URL) throws -> CurrentStoreSnapshot {
        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            sqlite3_close(database)
            throw PersistentStoreControllerError.sqliteOpenFailed(storeURL.path)
        }
        defer { sqlite3_close(database) }

        var papers = try readPapers(from: database)
        let tagNamesByPaperRowID = try readTagNames(from: database)
        papers = papers.map { paper in
            var updatedPaper = paper
            updatedPaper.tagNames = tagNamesByPaperRowID[paper.rowID] ?? []
            return updatedPaper
        }

        return CurrentStoreSnapshot(
            papers: papers,
            paperCards: try readPaperCards(from: database),
            annotations: try readAnnotations(from: database),
            settings: try readSettings(from: database),
            feedbackEntries: try readFeedbackEntries(from: database)
        )
    }

    private static func readPapers(from database: OpaquePointer) throws -> [CurrentStorePaperRecord] {
        let sql = """
        SELECT Z_PK, ZID, ZTITLE, ZAUTHORSTEXT, ZABSTRACTTEXT, ZVENUEKEY, ZVENUENAME, ZDOI, ZBIBTEX,
               ZSOURCEURLSTRING, ZPDFURLSTRING, ZCACHEDPDFPATH, ZSTATUSRAWVALUE, ZQUEUEPOSITION,
               ZDATEADDED, ZDUEDATE, ZMANUALDUEDATEOVERRIDE, ZSTARTEDAT, ZCOMPLETEDAT, ZNOTES,
               ZAUTOTAGGINGSTATUSMESSAGE
        FROM ZPAPER
        """
        let statement = try SQLiteStatement(database: database, sql: sql)
        defer { statement.finalize() }

        var papers: [CurrentStorePaperRecord] = []
        while statement.step() == SQLITE_ROW {
            let paper = CurrentStorePaperRecord(
                rowID: statement.int64(at: 0),
                id: try statement.uuid(at: 1),
                title: statement.string(at: 2) ?? "",
                authors: splitAuthors(statement.string(at: 3) ?? ""),
                abstractText: statement.string(at: 4) ?? "",
                venueKey: statement.string(at: 5),
                venueName: statement.string(at: 6),
                doi: statement.string(at: 7),
                bibtex: statement.string(at: 8),
                sourceURL: statement.url(at: 9),
                pdfURL: statement.url(at: 10),
                cachedPDFPath: statement.string(at: 11),
                statusRawValue: statement.string(at: 12) ?? PaperStatus.inbox.rawValue,
                queuePosition: Int(statement.int64(at: 13)),
                dateAdded: statement.date(at: 14) ?? .now,
                dueDate: statement.date(at: 15),
                manualDueDateOverride: statement.date(at: 16),
                startedAt: statement.date(at: 17),
                completedAt: statement.date(at: 18),
                notes: statement.string(at: 19) ?? "",
                autoTaggingStatusMessage: statement.string(at: 20),
                tagNames: []
            )
            papers.append(paper)
        }

        return papers
    }

    private static func readAnnotations(from database: OpaquePointer) throws -> [CurrentStoreAnnotationRecord] {
        guard tableExists("ZPAPERANNOTATION", in: database) else {
            return []
        }

        let sql = """
        SELECT ZID, ZPAPER, ZPAGEINDEX, ZQUOTEDTEXT, ZNOTETEXT, ZCOLORRAWVALUE,
               ZRECTPAYLOAD, ZCREATEDAT, ZUPDATEDAT
        FROM ZPAPERANNOTATION
        """
        let statement = try SQLiteStatement(database: database, sql: sql)
        defer { statement.finalize() }

        var annotations: [CurrentStoreAnnotationRecord] = []
        while statement.step() == SQLITE_ROW {
            annotations.append(
                CurrentStoreAnnotationRecord(
                    id: try statement.uuid(at: 0),
                    paperRowID: statement.int64(at: 1),
                    pageIndex: Int(statement.int64(at: 2)),
                    quotedText: statement.string(at: 3) ?? "",
                    noteText: statement.string(at: 4) ?? "",
                    colorRawValue: statement.string(at: 5) ?? ReaderHighlightColor.yellow.rawValue,
                    rectPayload: statement.string(at: 6) ?? "[]",
                    createdAt: statement.date(at: 7) ?? .now,
                    updatedAt: statement.date(at: 8) ?? .now
                )
            )
        }

        return annotations
    }

    private static func readPaperCards(from database: OpaquePointer) throws -> [CurrentStorePaperCardRecord] {
        guard tableExists("ZPAPERCARD", in: database) else {
            return []
        }

        let sql = """
        SELECT ZID, ZPAPER, ZCREATEDAT, ZUPDATEDAT, ZFORMATVERSION, ZHEADLINE, ZVENUELINE,
               ZCITATIONLINE, ZKEYWORDSPAYLOAD, ZSECTIONSPAYLOAD, ZHTMLCONTENT, ZHTMLEXPORTPATH
        FROM ZPAPERCARD
        """
        let statement = try SQLiteStatement(database: database, sql: sql)
        defer { statement.finalize() }

        var cards: [CurrentStorePaperCardRecord] = []
        while statement.step() == SQLITE_ROW {
            cards.append(
                CurrentStorePaperCardRecord(
                    id: try statement.uuid(at: 0),
                    paperRowID: statement.int64(at: 1),
                    createdAt: statement.date(at: 2) ?? .now,
                    updatedAt: statement.date(at: 3) ?? .now,
                    formatVersion: Int(statement.int64(at: 4)),
                    headline: statement.string(at: 5) ?? "",
                    venueLine: statement.string(at: 6) ?? "",
                    citationLine: statement.string(at: 7) ?? "",
                    keywordsPayload: statement.string(at: 8) ?? "[]",
                    sectionsPayload: statement.string(at: 9) ?? "[]",
                    htmlContent: statement.string(at: 10) ?? "",
                    htmlExportPath: statement.string(at: 11)
                )
            )
        }

        return cards
    }

    private static func readTagNames(from database: OpaquePointer) throws -> [Int64: [String]] {
        let statement = try SQLiteStatement(database: database, sql: "SELECT ZPAPER, ZNAME FROM ZTAG")
        defer { statement.finalize() }

        var tagNamesByPaperRowID: [Int64: [String]] = [:]
        while statement.step() == SQLITE_ROW {
            let paperRowID = statement.int64(at: 0)
            let tagName = statement.string(at: 1) ?? ""
            guard tagName.isEmpty == false else { continue }
            tagNamesByPaperRowID[paperRowID, default: []].append(tagName)
        }

        return tagNamesByPaperRowID
    }

    private static func readSettings(from database: OpaquePointer) throws -> [CurrentStoreSettingsRecord] {
        let sql = """
        SELECT ZID, ZPAPERSPERDAY, ZDAILYREMINDERTIME, ZAUTOCACHEPDFS,
               ZDEFAULTIMPORTBEHAVIORRAWVALUE, ZAITAGGINGENABLED,
               ZAITAGGINGBASEURLSTRING, ZAITAGGINGMODEL
        FROM ZUSERSETTINGS
        """
        let statement = try SQLiteStatement(database: database, sql: sql)
        defer { statement.finalize() }

        var settings: [CurrentStoreSettingsRecord] = []
        while statement.step() == SQLITE_ROW {
            settings.append(
                CurrentStoreSettingsRecord(
                    id: try statement.uuid(at: 0),
                    papersPerDay: Int(statement.int64(at: 1)),
                    dailyReminderTime: statement.date(at: 2) ?? UserSettings.defaultReminderDate(),
                    autoCachePDFs: statement.bool(at: 3),
                    defaultImportBehaviorRawValue: statement.string(at: 4) ?? ImportBehavior.scheduleImmediately.rawValue,
                    aiTaggingEnabled: statement.bool(at: 5),
                    aiTaggingBaseURLString: statement.string(at: 6) ?? "https://api.openai.com/v1",
                    aiTaggingModel: statement.string(at: 7) ?? "gpt-4o-mini"
                )
            )
        }

        return settings
    }

    private static func readFeedbackEntries(from database: OpaquePointer) throws -> [CurrentStoreFeedbackEntryRecord] {
        let sql = """
        SELECT ZID, ZCREATEDAT, ZSCREENRAWVALUE, ZSCREENTITLE, ZSELECTEDPAPERID,
               ZSELECTEDPAPERTITLE, ZSELECTEDPAPERSTATUSRAWVALUE, ZINTENDEDACTION, ZFEEDBACKTEXT
        FROM ZFEEDBACKENTRY
        """
        let statement = try SQLiteStatement(database: database, sql: sql)
        defer { statement.finalize() }

        var entries: [CurrentStoreFeedbackEntryRecord] = []
        while statement.step() == SQLITE_ROW {
            entries.append(
                CurrentStoreFeedbackEntryRecord(
                    id: try statement.uuid(at: 0),
                    createdAt: statement.date(at: 1) ?? .now,
                    screenRawValue: statement.string(at: 2) ?? AppScreen.queue.rawValue,
                    screenTitle: statement.string(at: 3) ?? AppScreen.queue.title,
                    selectedPaperID: try statement.optionalUUID(at: 4),
                    selectedPaperTitle: statement.string(at: 5),
                    selectedPaperStatusRawValue: statement.string(at: 6),
                    intendedAction: statement.string(at: 7) ?? "",
                    feedbackText: statement.string(at: 8) ?? ""
                )
            )
        }

        return entries
    }

    private static func splitAuthors(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private static func tableExists(_ tableName: String, in database: OpaquePointer) -> Bool {
        let escapedTableName = tableName.replacingOccurrences(of: "'", with: "''")
        let sql = """
        SELECT 1
        FROM sqlite_master
        WHERE type = 'table' AND name = '\(escapedTableName)'
        LIMIT 1
        """
        guard let statement = try? SQLiteStatement(database: database, sql: sql) else {
            return false
        }
        defer { statement.finalize() }

        return statement.step() == SQLITE_ROW
    }
}

private final class SQLiteStatement {
    private var statement: OpaquePointer?

    init(database: OpaquePointer, sql: String) throws {
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            let message = String(cString: sqlite3_errmsg(database))
            throw PersistentStoreControllerError.sqlitePrepareFailed(message)
        }
        self.statement = statement
    }

    func step() -> Int32 {
        sqlite3_step(statement)
    }

    func finalize() {
        sqlite3_finalize(statement)
        statement = nil
    }

    func string(at index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    func int64(at index: Int32) -> Int64 {
        sqlite3_column_int64(statement, index)
    }

    func bool(at index: Int32) -> Bool {
        sqlite3_column_int64(statement, index) != 0
    }

    func date(at index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, index))
    }

    func url(at index: Int32) -> URL? {
        string(at: index).flatMap(URL.init(string:))
    }

    func uuid(at index: Int32) throws -> UUID {
        guard let data = blob(at: index),
              let uuid = data.uuidValue else {
            throw PersistentStoreControllerError.invalidUUIDData
        }
        return uuid
    }

    func optionalUUID(at index: Int32) throws -> UUID? {
        guard let data = blob(at: index) else { return nil }
        guard let uuid = data.uuidValue else {
            throw PersistentStoreControllerError.invalidUUIDData
        }
        return uuid
    }

    private func blob(at index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let rawBytes = sqlite3_column_blob(statement, index) else {
            return nil
        }
        let count = Int(sqlite3_column_bytes(statement, index))
        return Data(bytes: rawBytes, count: count)
    }
}

private extension Data {
    var uuidValue: UUID? {
        guard count == MemoryLayout<uuid_t>.size else { return nil }
        let bytes = [UInt8](self)
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

enum PaperMasterLegacySchemaV1: VersionedSchema {
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

enum PaperMasterSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
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
    }

    @Model
    final class Tag {
        @Attribute(.unique) var name: String

        init(name: String) {
            self.name = name
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

enum PaperMasterSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
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
        var managedPDFLocalPath: String?
        var managedPDFRemoteURLString: String?
        var statusRawValue: String
        var queuePosition: Int
        var dateAdded: Date
        var dueDate: Date?
        var manualDueDateOverride: Date?
        var startedAt: Date?
        var completedAt: Date?
        var notes: String
        var autoTaggingStatusMessage: String?
        @Relationship(deleteRule: .cascade, inverse: \Tag.paper) var tags: [Tag]

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
            managedPDFLocalPath: String? = nil,
            managedPDFRemoteURLString: String? = nil,
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
            self.managedPDFLocalPath = managedPDFLocalPath
            self.managedPDFRemoteURLString = managedPDFRemoteURLString
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
    }

    @Model
    final class Tag {
        var name: String
        var paper: Paper?

        init(name: String, paper: Paper? = nil) {
            self.name = Tag.normalize(name)
            self.paper = paper
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
        var paperStorageModeRawValueStorage: String?
        var customPaperStoragePathStorage: String?
        var remotePaperStorageHostStorage: String?
        var remotePaperStoragePortStorage: Int?
        var remotePaperStorageUsernameStorage: String?
        var remotePaperStorageDirectoryStorage: String?
        var aiTaggingEnabled: Bool
        var aiTaggingBaseURLString: String
        var aiTaggingModel: String

        init(
            id: UUID = UUID(),
            papersPerDay: Int = 1,
            dailyReminderTime: Date = UserSettings.defaultReminderDate(),
            autoCachePDFs: Bool = false,
            defaultImportBehaviorRawValue: String = ImportBehavior.scheduleImmediately.rawValue,
            paperStorageModeRawValueStorage: String? = PaperStorageMode.defaultLocal.rawValue,
            customPaperStoragePathStorage: String? = "",
            remotePaperStorageHostStorage: String? = "",
            remotePaperStoragePortStorage: Int? = 22,
            remotePaperStorageUsernameStorage: String? = "",
            remotePaperStorageDirectoryStorage: String? = "",
            aiTaggingEnabled: Bool = false,
            aiTaggingBaseURLString: String = "https://api.openai.com/v1",
            aiTaggingModel: String = "gpt-4o-mini"
        ) {
            self.id = id
            self.papersPerDay = papersPerDay
            self.dailyReminderTime = dailyReminderTime
            self.autoCachePDFs = autoCachePDFs
            self.defaultImportBehaviorRawValue = defaultImportBehaviorRawValue
            self.paperStorageModeRawValueStorage = paperStorageModeRawValueStorage
            self.customPaperStoragePathStorage = customPaperStoragePathStorage
            self.remotePaperStorageHostStorage = remotePaperStorageHostStorage
            self.remotePaperStoragePortStorage = remotePaperStoragePortStorage
            self.remotePaperStorageUsernameStorage = remotePaperStorageUsernameStorage
            self.remotePaperStorageDirectoryStorage = remotePaperStorageDirectoryStorage
            self.aiTaggingEnabled = aiTaggingEnabled
            self.aiTaggingBaseURLString = aiTaggingBaseURLString
            self.aiTaggingModel = aiTaggingModel
        }

        static func defaultReminderDate(calendar: Calendar = .current) -> Date {
            let now = Date()
            return calendar.date(
                bySettingHour: 9,
                minute: 0,
                second: 0,
                of: now
            ) ?? now
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

enum PaperMasterSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(4, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Paper.self, PaperAnnotation.self, Tag.self, UserSettings.self, FeedbackEntry.self]
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
        var managedPDFLocalPath: String?
        var managedPDFRemoteURLString: String?
        var statusRawValue: String
        var queuePosition: Int
        var dateAdded: Date
        var dueDate: Date?
        var manualDueDateOverride: Date?
        var startedAt: Date?
        var completedAt: Date?
        var notes: String
        var autoTaggingStatusMessage: String?
        @Relationship(deleteRule: .cascade, inverse: \Tag.paper) var tags: [Tag]
        @Relationship(deleteRule: .cascade, inverse: \PaperAnnotation.paper) var annotations: [PaperAnnotation]

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
            managedPDFLocalPath: String? = nil,
            managedPDFRemoteURLString: String? = nil,
            statusRawValue: String = PaperStatus.inbox.rawValue,
            queuePosition: Int = 0,
            dateAdded: Date = .now,
            dueDate: Date? = nil,
            manualDueDateOverride: Date? = nil,
            startedAt: Date? = nil,
            completedAt: Date? = nil,
            notes: String = "",
            autoTaggingStatusMessage: String? = nil,
            tags: [Tag] = [],
            annotations: [PaperAnnotation] = []
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
            self.managedPDFLocalPath = managedPDFLocalPath
            self.managedPDFRemoteURLString = managedPDFRemoteURLString
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
            self.annotations = annotations
        }
    }

    @Model
    final class PaperAnnotation {
        @Attribute(.unique) var id: UUID
        var pageIndex: Int
        var quotedText: String
        var noteText: String
        var colorRawValue: String
        var rectPayload: String
        var createdAt: Date
        var updatedAt: Date
        var paper: Paper?

        init(
            id: UUID = UUID(),
            pageIndex: Int,
            quotedText: String,
            noteText: String = "",
            colorRawValue: String = ReaderHighlightColor.yellow.rawValue,
            rectPayload: String,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            paper: Paper? = nil
        ) {
            self.id = id
            self.pageIndex = pageIndex
            self.quotedText = quotedText
            self.noteText = noteText
            self.colorRawValue = colorRawValue
            self.rectPayload = rectPayload
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.paper = paper
        }
    }

    @Model
    final class Tag {
        var name: String
        var paper: Paper?

        init(name: String, paper: Paper? = nil) {
            self.name = name
            self.paper = paper
        }
    }

    @Model
    final class UserSettings {
        @Attribute(.unique) var id: UUID
        var papersPerDay: Int
        var dailyReminderTime: Date
        var autoCachePDFs: Bool
        var defaultImportBehaviorRawValue: String
        var paperStorageModeRawValueStorage: String?
        var customPaperStoragePathStorage: String?
        var remotePaperStorageHostStorage: String?
        var remotePaperStoragePortStorage: Int?
        var remotePaperStorageUsernameStorage: String?
        var remotePaperStorageDirectoryStorage: String?
        var aiTaggingEnabled: Bool
        var aiTaggingBaseURLString: String
        var aiTaggingModel: String

        init(
            id: UUID = UUID(),
            papersPerDay: Int = 1,
            dailyReminderTime: Date = UserSettings.defaultReminderDate(),
            autoCachePDFs: Bool = false,
            defaultImportBehaviorRawValue: String = ImportBehavior.scheduleImmediately.rawValue,
            paperStorageModeRawValueStorage: String? = PaperStorageMode.defaultLocal.rawValue,
            customPaperStoragePathStorage: String? = "",
            remotePaperStorageHostStorage: String? = "",
            remotePaperStoragePortStorage: Int? = 22,
            remotePaperStorageUsernameStorage: String? = "",
            remotePaperStorageDirectoryStorage: String? = "",
            aiTaggingEnabled: Bool = false,
            aiTaggingBaseURLString: String = "https://api.openai.com/v1",
            aiTaggingModel: String = "gpt-4o-mini"
        ) {
            self.id = id
            self.papersPerDay = papersPerDay
            self.dailyReminderTime = dailyReminderTime
            self.autoCachePDFs = autoCachePDFs
            self.defaultImportBehaviorRawValue = defaultImportBehaviorRawValue
            self.paperStorageModeRawValueStorage = paperStorageModeRawValueStorage
            self.customPaperStoragePathStorage = customPaperStoragePathStorage
            self.remotePaperStorageHostStorage = remotePaperStorageHostStorage
            self.remotePaperStoragePortStorage = remotePaperStoragePortStorage
            self.remotePaperStorageUsernameStorage = remotePaperStorageUsernameStorage
            self.remotePaperStorageDirectoryStorage = remotePaperStorageDirectoryStorage
            self.aiTaggingEnabled = aiTaggingEnabled
            self.aiTaggingBaseURLString = aiTaggingBaseURLString
            self.aiTaggingModel = aiTaggingModel
        }

        static func defaultReminderDate(calendar: Calendar = .current) -> Date {
            let now = Date()
            return calendar.date(
                bySettingHour: 9,
                minute: 0,
                second: 0,
                of: now
            ) ?? now
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

enum PaperMasterSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(5, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Paper.self, PaperAnnotation.self, Tag.self, UserSettings.self, FeedbackEntry.self, PaperCard.self]
    }
}

enum PaperMasterMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PaperMasterSchemaV2.self, PaperMasterSchemaV3.self, PaperMasterSchemaV4.self, PaperMasterSchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: PaperMasterSchemaV2.self,
                toVersion: PaperMasterSchemaV3.self
            ),
            .lightweight(
                fromVersion: PaperMasterSchemaV3.self,
                toVersion: PaperMasterSchemaV4.self
            ),
            .lightweight(
                fromVersion: PaperMasterSchemaV4.self,
                toVersion: PaperMasterSchemaV5.self
            )
        ]
    }
}
