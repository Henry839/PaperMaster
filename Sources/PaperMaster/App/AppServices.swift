import AppKit
import Foundation
import Observation
import SwiftData

struct PresentedError: Identifiable {
    let id = UUID()
    let message: String
}

struct PresentedNotice: Identifiable {
    let id = UUID()
    let message: String
}

enum ReaderCompanionRequestResult: Equatable {
    case comment(ReaderCompanionOutput)
    case noComment
    case paused(ReaderElfPauseReason)
}

protocol TextClipboardWriting: Sendable {
    func setString(_ string: String)
}

struct SystemTextClipboardWriter: TextClipboardWriting {
    func setString(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

@MainActor
@Observable
final class AppServices {
    let importService: PaperImportService
    let fusionGenerator: PaperFusionGenerating?
    let paperCardGenerator: PaperCardGenerating?
    let readerAnswerer: ReaderAnswerGenerating?
    let readerCompanionGenerator: ReaderCompanionGenerating?
    let schedulerService: SchedulerService
    let pdfCacheService: PDFCacheService
    let paperStorageService: PaperStorageService
    let reminderService: ReminderService
    let taggingCredentialStore: TaggingCredentialStoring
    let paperStorageCredentialStore: PaperStorageCredentialStoring
    let readerDocumentContextLoader: ReaderDocumentContextLoading
    let textClipboard: TextClipboardWriting
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let paperCardHTMLDirectoryURL: URL
    @ObservationIgnored private let agentImportDirectoryURL: URL
    @ObservationIgnored private let startupNoticeMessage: String?
    @ObservationIgnored private let startupErrorMessage: String?
    @ObservationIgnored private var noticeDismissTask: Task<Void, Never>?
    @ObservationIgnored private var importStatusDismissTask: Task<Void, Never>?
    @ObservationIgnored private var storageFolderMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var monitoredImportDirectorySignature: String?
    @ObservationIgnored private var activeLocalImportPaths: Set<String> = []
    private(set) var didBootstrap = false
    var presentedError: PresentedError?
    var presentedNotice: PresentedNotice?
    var importStatusMessage: String?

    init(
        importService: PaperImportService,
        fusionGenerator: PaperFusionGenerating? = nil,
        paperCardGenerator: PaperCardGenerating? = nil,
        readerAnswerer: ReaderAnswerGenerating? = nil,
        readerCompanionGenerator: ReaderCompanionGenerating? = nil,
        schedulerService: SchedulerService = SchedulerService(),
        pdfCacheService: PDFCacheService = PDFCacheService(),
        paperStorageService: PaperStorageService = PaperStorageService(),
        reminderService: ReminderService = ReminderService(),
        taggingCredentialStore: TaggingCredentialStoring = InMemoryTaggingCredentialStore(),
        paperStorageCredentialStore: PaperStorageCredentialStoring = InMemoryPaperStorageCredentialStore(),
        readerDocumentContextLoader: ReaderDocumentContextLoading = PDFKitReaderDocumentContextLoader(),
        textClipboard: TextClipboardWriting = SystemTextClipboardWriter(),
        fileManager: FileManager = .default,
        paperCardHTMLDirectoryURL: URL? = nil,
        agentImportDirectoryURL: URL? = nil,
        startupNoticeMessage: String? = nil,
        startupErrorMessage: String? = nil
    ) {
        self.importService = importService
        self.fusionGenerator = fusionGenerator
        self.paperCardGenerator = paperCardGenerator
        self.readerAnswerer = readerAnswerer
        self.readerCompanionGenerator = readerCompanionGenerator
        self.schedulerService = schedulerService
        self.pdfCacheService = pdfCacheService
        self.paperStorageService = paperStorageService
        self.reminderService = reminderService
        self.taggingCredentialStore = taggingCredentialStore
        self.paperStorageCredentialStore = paperStorageCredentialStore
        self.readerDocumentContextLoader = readerDocumentContextLoader
        self.textClipboard = textClipboard
        self.fileManager = fileManager
        let defaultPaperCardDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PaperMaster", isDirectory: true)
            .appendingPathComponent("PaperCards", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("PaperMaster", isDirectory: true)
                .appendingPathComponent("PaperCards", isDirectory: true)
        self.paperCardHTMLDirectoryURL = paperCardHTMLDirectoryURL ?? defaultPaperCardDirectoryURL
        self.agentImportDirectoryURL = agentImportDirectoryURL ?? AgentWorkspacePaths.default(fileManager: fileManager).attachmentsDirectoryURL
        self.startupNoticeMessage = startupNoticeMessage
        self.startupErrorMessage = startupErrorMessage
    }

    static func live(
        startupNoticeMessage: String? = nil,
        startupErrorMessage: String? = nil
    ) -> AppServices {
        let resolver = MetadataResolver()
        let taggingCredentialStore = KeychainTaggingCredentialStore()
        let paperStorageCredentialStore = KeychainPaperStorageCredentialStore()
        return AppServices(
            importService: PaperImportService(
                metadataResolver: resolver,
                publicationEnricher: CrossrefPublicationEnricher(),
                tagGenerator: OpenAICompatiblePaperTagger(),
                credentialStore: taggingCredentialStore
            ),
            fusionGenerator: OpenAICompatiblePaperFusionGenerator(),
            paperCardGenerator: OpenAICompatiblePaperCardGenerator(),
            readerAnswerer: OpenAICompatibleReaderAnswerer(),
            readerCompanionGenerator: OpenAICompatibleReaderCompanionGenerator(),
            paperStorageService: PaperStorageService(
                credentialStore: paperStorageCredentialStore
            ),
            taggingCredentialStore: taggingCredentialStore,
            paperStorageCredentialStore: paperStorageCredentialStore,
            startupNoticeMessage: startupNoticeMessage,
            startupErrorMessage: startupErrorMessage
        )
    }

    var defaultPaperStorageDirectoryPath: String {
        paperStorageService.defaultStorageDirectoryURL.path
    }

    var defaultPaperStorageDirectoryURL: URL {
        paperStorageService.defaultStorageDirectoryURL
    }

    func bootstrap(in context: ModelContext, settings existingSettings: [UserSettings], papers: [Paper]) async {
        let settings = ensureSettings(in: context, existingSettings: existingSettings)
        guard didBootstrap == false else { return }

        await reminderService.requestAuthorization()
        schedulerService.applySchedule(to: papers, papersPerDay: settings.papersPerDay)
        try? context.save()
        try? fileManager.createDirectory(at: agentImportDirectoryURL, withIntermediateDirectories: true)
        await reminderService.syncNotifications(for: papers, settings: settings)
        if let startupErrorMessage {
            presentedError = PresentedError(message: startupErrorMessage)
        } else if let startupNoticeMessage {
            showNotice(startupNoticeMessage)
        }
        didBootstrap = true
        refreshStorageFolderMonitoring(context: context)
    }

    @discardableResult
    func ensureSettings(in context: ModelContext, existingSettings: [UserSettings]) -> UserSettings {
        if let first = existingSettings.first {
            return first
        }

        let settings = UserSettings()
        context.insert(settings)
        try? context.save()
        return settings
    }

    func importPaper(
        request: PaperCaptureRequest,
        settings: UserSettings,
        currentPapers: [Paper],
        in context: ModelContext
    ) async -> Paper? {
        await performImportPaper(
            request: request,
            settings: settings,
            currentPapers: currentPapers,
            in: context,
            reportsProgress: false
        )
    }

    func startImportPaper(
        request: PaperCaptureRequest,
        settings: UserSettings,
        currentPapers: [Paper],
        in context: ModelContext,
        onCompletion: (@MainActor (Paper?) -> Void)? = nil
    ) {
        updateImportStatus("Importing paper (1/3): fetching metadata and preparing the paper.")

        Task { @MainActor [weak self] in
            guard let self else { return }
            let paper = await self.performImportPaper(
                request: request,
                settings: settings,
                currentPapers: currentPapers,
                in: context,
                reportsProgress: true
            )
            onCompletion?(paper)
        }
    }

    private func performImportPaper(
        request: PaperCaptureRequest,
        settings: UserSettings,
        currentPapers: [Paper],
        in context: ModelContext,
        reportsProgress: Bool
    ) async -> Paper? {
        do {
            let result = try await importService.createPaper(from: request, settings: settings, in: context)
            let paper = result.paper
            if result.didCreatePaper == false {
                if let notice = result.notice {
                    showNotice(notice)
                }
                if reportsProgress {
                    completeImportStatus("Import complete: that paper is already in your library.")
                }
                return paper
            }
            let existingPapers = (try? context.fetch(FetchDescriptor<Paper>())) ?? currentPapers
            let papersExcludingImported = existingPapers.filter { $0.id != paper.id }
            paper.manualDueDateOverride = nil
            if paper.status.isActiveQueue {
                paper.queuePosition = nextQueuePosition(in: papersExcludingImported)
            }
            if reportsProgress {
                updateImportStatus("Importing paper (2/3): saving the PDF and library metadata.")
            }
            let storageNotice = await storeManagedPDFIfPossible(for: paper, settings: settings)
            let syncedPapers = papersExcludingImported + [paper]
            if reportsProgress {
                updateImportStatus("Importing paper (3/3): updating your reading queue and reminders.")
            }
            try persistAndSync(allPapers: syncedPapers, settings: settings, context: context)
            refreshStorageFolderMonitoring(context: context)
            if let notice = combinedNoticeMessages(result.notice, storageNotice) {
                showNotice(notice)
            }
            if reportsProgress {
                completeImportStatus("Import complete: the paper is ready in your library.")
            }
            return paper
        } catch {
            if reportsProgress {
                failImportStatus("Import failed: \(error.localizedDescription)")
            }
            present(error)
            return nil
        }
    }

    func updatePaperStatus(
        _ paper: Paper,
        status: PaperStatus,
        allPapers: [Paper],
        settings: UserSettings,
        context: ModelContext
    ) {
        let previousStatus = paper.status
        paper.status = status

        switch status {
        case .reading:
            if previousStatus.isActiveQueue == false {
                paper.queuePosition = nextQueuePosition(in: allPapers)
            }
            paper.manualDueDateOverride = nil
            paper.startedAt = paper.startedAt ?? .now
            paper.completedAt = nil
        case .done:
            paper.manualDueDateOverride = nil
            paper.completedAt = .now
        case .inbox:
            paper.manualDueDateOverride = nil
            paper.startedAt = nil
            paper.completedAt = nil
            paper.dueDate = nil
        case .scheduled:
            if previousStatus.isActiveQueue == false {
                paper.queuePosition = nextQueuePosition(in: allPapers)
            }
            paper.manualDueDateOverride = nil
            paper.completedAt = nil
        case .archived:
            paper.manualDueDateOverride = nil
            paper.completedAt = paper.completedAt ?? .now
            paper.dueDate = nil
        }

        do {
            try persistAndSync(allPapers: allPapers, settings: settings, context: context)
        } catch {
            present(error)
        }
    }

    func snooze(
        paper: Paper,
        byDays days: Int,
        allPapers: [Paper],
        settings: UserSettings,
        context: ModelContext
    ) {
        let baseDate = Calendar.current.startOfDay(for: .now)
        paper.status = .scheduled
        paper.manualDueDateOverride = Calendar.current.date(byAdding: .day, value: max(1, days), to: baseDate)

        do {
            try persistAndSync(allPapers: allPapers, settings: settings, context: context)
        } catch {
            present(error)
        }
    }

    func replanQueueFromToday(
        papers: [Paper],
        settings: UserSettings,
        context: ModelContext,
        referenceDate: Date = .now
    ) {
        let calendar = schedulerService.calendar
        let today = calendar.startOfDay(for: referenceDate)
        let overdueScheduledPapers = papers.filter { paper in
            guard paper.status == .scheduled,
                  let dueDate = paper.dueDate else {
                return false
            }
            return calendar.startOfDay(for: dueDate) < today
        }

        guard overdueScheduledPapers.isEmpty == false else { return }

        for paper in overdueScheduledPapers {
            paper.dueDate = nil
        }

        do {
            try persistAndSync(
                allPapers: papers,
                settings: settings,
                context: context,
                referenceDate: referenceDate
            )
            let noun = overdueScheduledPapers.count == 1 ? "paper" : "papers"
            showNotice("Replanned \(overdueScheduledPapers.count) overdue \(noun) from today.")
        } catch {
            present(error)
        }
    }

    func move(
        paper: Paper,
        by offset: Int,
        allPapers: [Paper],
        settings: UserSettings,
        context: ModelContext
    ) {
        let queue = queuedPapers(from: allPapers)
        guard let currentIndex = queue.firstIndex(where: { $0.id == paper.id }) else { return }

        move(
            paper: paper,
            toQueueIndex: currentIndex + offset,
            allPapers: allPapers,
            settings: settings,
            context: context
        )
    }

    func move(
        paper: Paper,
        toQueueIndex destinationIndex: Int,
        allPapers: [Paper],
        settings: UserSettings,
        context: ModelContext
    ) {
        var queue = queuedPapers(from: allPapers)
        guard let currentIndex = queue.firstIndex(where: { $0.id == paper.id }) else { return }

        let normalizedIndex = min(max(0, destinationIndex), queue.count - 1)
        guard normalizedIndex != currentIndex else { return }

        let moved = queue.remove(at: currentIndex)
        queue.insert(moved, at: normalizedIndex)

        for (index, item) in queue.enumerated() {
            item.queuePosition = index
            if item.id == paper.id {
                item.manualDueDateOverride = nil
            }
        }

        do {
            try persistAndSync(allPapers: allPapers, settings: settings, context: context)
        } catch {
            present(error)
        }
    }

    func updateTags(
        for paper: Paper,
        tagString: String,
        allPapers: [Paper],
        settings: UserSettings,
        context: ModelContext
    ) {
        do {
            replaceTags(
                for: paper,
                with: resolveTags(from: tagString),
                in: context
            )
            paper.autoTaggingStatusMessage = nil
            try persistAndSync(allPapers: allPapers, settings: settings, context: context)
        } catch {
            present(error)
        }
    }

    func refreshScheduleAndNotifications(
        papers: [Paper],
        settings: UserSettings,
        context: ModelContext
    ) {
        do {
            try persistAndSync(allPapers: papers, settings: settings, context: context)
        } catch {
            present(error)
        }
    }

    func refreshStorageFolderMonitoring(context: ModelContext) {
        let settings = (try? context.fetch(FetchDescriptor<UserSettings>()).first) ?? nil
        let monitoredDirectorySignature = settings.map(monitoredImportDirectorySignature(for:)) ?? nil

        guard monitoredImportDirectorySignature != monitoredDirectorySignature || storageFolderMonitorTask == nil else {
            return
        }

        storageFolderMonitorTask?.cancel()
        monitoredImportDirectorySignature = monitoredDirectorySignature

        guard monitoredDirectorySignature != nil else {
            storageFolderMonitorTask = nil
            return
        }

        storageFolderMonitorTask = Task { @MainActor [weak self] in
            await self?.runStorageFolderMonitoring(context: context)
        }
    }

    func importDroppedPDFs(
        at fileURLs: [URL],
        settings: UserSettings,
        currentPapers: [Paper],
        in context: ModelContext
    ) async {
        guard fileURLs.isEmpty == false else { return }

        let totalCount = Array(Set(fileURLs.map(\.standardizedFileURL))).count
        updateImportStatus("Preparing to import \(totalCount) PDF\(totalCount == 1 ? "" : "s").")

        let outcomes = await importLocalPDFs(
            at: fileURLs,
            settings: settings,
            currentPapers: currentPapers,
            in: context,
            origin: .drop
        )

        let importedCount = outcomes.filter(\.didCreatePaper).count
        if importedCount > 0 {
            let noun = importedCount == 1 ? "paper" : "papers"
            showNotice("Imported \(importedCount) \(noun) from dropped PDFs.")
        }

        let summary = importedCount == 0
            ? "No new papers were imported."
            : "Imported \(importedCount) of \(totalCount) PDFs."
        completeImportStatus(summary)
    }

    func persistNotes(context: ModelContext) {
        do {
            try context.save()
        } catch {
            present(error)
        }
    }

    @discardableResult
    func saveAnnotation(
        for paper: Paper,
        selection: ReaderSelectionSnapshot,
        color: ReaderHighlightColor,
        context: ModelContext
    ) -> PaperAnnotation? {
        if let existingAnnotation = paper.annotations.first(where: { $0.matches(selection) }) {
            if existingAnnotation.color != color {
                existingAnnotation.color = color
                existingAnnotation.touch()
            }
            persistNotes(context: context)
            return existingAnnotation
        }

        let annotation = PaperAnnotation(
            paper: paper,
            pageIndex: selection.pageIndex,
            quotedText: selection.quotedText,
            color: color,
            rectPayload: selection.rectPayload
        )
        context.insert(annotation)
        persistNotes(context: context)
        return annotation
    }

    func updateAnnotationColor(
        _ annotation: PaperAnnotation,
        color: ReaderHighlightColor,
        context: ModelContext
    ) {
        guard annotation.color != color else { return }
        annotation.color = color
        annotation.touch()
        persistNotes(context: context)
    }

    func deleteAnnotation(_ annotation: PaperAnnotation, context: ModelContext) {
        context.delete(annotation)
        persistNotes(context: context)
    }

    func loadTaggingAPIKey() -> String {
        do {
            return try taggingCredentialStore.loadAPIKey() ?? ""
        } catch {
            present(error)
            return ""
        }
    }

    func loadReaderDocumentContext(from fileURL: URL) -> ReaderAskAIDocumentContext {
        let context = readerDocumentContextLoader.loadDocumentContext(from: fileURL)
        if context.hasUsableText == false {
            showNotice("Couldn't extract full paper text. Ask AI will use the selection and paper metadata only.")
        }
        return context
    }

    func answerReaderQuestion(
        _ question: String,
        for paper: Paper,
        selection: ReaderSelectionSnapshot,
        settings: UserSettings,
        documentContext: ReaderAskAIDocumentContext
    ) async -> String? {
        guard let readerAnswerer else {
            present(ReaderAnswerError.generatorUnavailable)
            return nil
        }

        let storedAPIKey: String?
        do {
            storedAPIKey = try taggingCredentialStore.loadAPIKey()
        } catch {
            present(error)
            return nil
        }

        guard let configuration = settings.aiProviderConfiguration(apiKey: storedAPIKey) else {
            let readiness = settings.aiProviderReadiness(apiKey: storedAPIKey)
            present(ReaderAnswerError.providerNotConfigured(readiness.settingsMessage))
            return nil
        }

        let input = ReaderAskAIInput(
            question: question.trimmingCharacters(in: .whitespacesAndNewlines),
            quotedText: selection.quotedText,
            pageNumber: selection.pageNumber,
            paperTitle: paper.title.trimmingCharacters(in: .whitespacesAndNewlines),
            authorsText: paper.authorsDisplayText,
            abstractText: truncated(paper.abstractText, limit: 1_400),
            tagNames: Array(paper.tagNames.prefix(8)),
            documentText: documentContext.documentText,
            documentWasTruncated: documentContext.documentWasTruncated
        )

        do {
            return try await readerAnswerer.answerQuestion(for: input, configuration: configuration)
        } catch {
            present(error)
            return nil
        }
    }

    func requestReaderCompanionComment(
        for paper: Paper,
        passage: ReaderFocusPassageSnapshot,
        recentComments: [ReaderElfComment],
        settings: UserSettings,
        documentContext: ReaderAskAIDocumentContext
    ) async -> ReaderCompanionRequestResult {
        guard let readerCompanionGenerator else {
            return .paused(ReaderElfPauseReason(ReaderCompanionError.generatorUnavailable.localizedDescription))
        }

        let storedAPIKey: String?
        do {
            storedAPIKey = try taggingCredentialStore.loadAPIKey()
        } catch {
            return .paused(ReaderElfPauseReason(error.localizedDescription))
        }

        guard let configuration = settings.aiProviderConfiguration(apiKey: storedAPIKey) else {
            let readiness = settings.aiProviderReadiness(apiKey: storedAPIKey)
            return .paused(ReaderElfPauseReason(readiness.settingsMessage))
        }

        let input = ReaderCompanionInput(
            focusPassage: passage,
            paperTitle: paper.title.trimmingCharacters(in: .whitespacesAndNewlines),
            authorsText: paper.authorsDisplayText,
            abstractText: truncated(paper.abstractText, limit: 1_400),
            tagNames: Array(paper.tagNames.prefix(8)),
            documentText: documentContext.documentText,
            documentWasTruncated: documentContext.documentWasTruncated,
            recentComments: recentComments
        )

        do {
            let output = try await readerCompanionGenerator.generateComment(for: input, configuration: configuration)
            return output.shouldInterrupt ? .comment(output) : .noComment
        } catch {
            return .paused(ReaderElfPauseReason(error.localizedDescription))
        }
    }

    func generatePaperCard(
        for paper: Paper,
        settings: UserSettings,
        allPapers: [Paper],
        context: ModelContext
    ) async {
        guard let paperCardGenerator else {
            present(PaperCardError.generatorUnavailable)
            return
        }

        let storedAPIKey: String?
        do {
            storedAPIKey = try taggingCredentialStore.loadAPIKey()
        } catch {
            present(error)
            return
        }

        guard let configuration = settings.aiProviderConfiguration(apiKey: storedAPIKey) else {
            let readiness = settings.aiProviderReadiness(apiKey: storedAPIKey)
            present(PaperCardError.providerNotConfigured(readiness.settingsMessage))
            return
        }

        let venueText = [paper.venueName, paper.venueKey]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " · ")
        let citationText = [
            paper.doi.map { "DOI: \($0)" },
            paper.bibtex?.isEmpty == false ? "BibTeX available" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        let input = PaperCardInput(
            paperTitle: paper.title,
            authorsText: paper.authorsDisplayText,
            abstractText: truncated(paper.abstractText, limit: 3_200),
            venueText: venueText.isEmpty ? "Unknown venue" : venueText,
            citationText: citationText.isEmpty ? "Citation info unavailable" : citationText,
            tagNames: Array(paper.tagNames.prefix(10)),
            notesText: truncated(paper.notes, limit: 800)
        )

        do {
            let output = try await paperCardGenerator.generatePaperCard(for: input, configuration: configuration)
            let htmlContent = PaperCardHTMLRenderer().render(card: output, paper: paper)
            let exportURL = try writePaperCardHTML(htmlContent, for: paper)

            if let existingCard = paper.paperCard {
                existingCard.update(
                    headline: output.headline,
                    venueLine: output.venueLine,
                    citationLine: output.citationLine,
                    keywords: output.keywords,
                    sections: output.sections,
                    htmlContent: htmlContent
                )
                existingCard.htmlExportURL = exportURL
            } else {
                let card = PaperCard(
                    paper: paper,
                    headline: output.headline,
                    venueLine: output.venueLine,
                    citationLine: output.citationLine,
                    keywords: output.keywords,
                    sections: output.sections,
                    htmlContent: htmlContent,
                    htmlExportPath: exportURL.path
                )
                context.insert(card)
                paper.paperCard = card
            }

            try persistAndSync(allPapers: allPapers, settings: settings, context: context)
            showNotice("Paper Card generated and saved locally.")
        } catch {
            present(error)
        }
    }

    func copyPaperCardText(_ card: PaperCard) {
        copyText(card.plainTextExport, notice: "Copied Paper Card.")
    }

    func copyPaperCardHTML(_ card: PaperCard) {
        copyText(card.htmlContent, notice: "Copied Paper Card HTML.")
    }

    func openPaperCardHTML(_ card: PaperCard, paper: Paper) {
        let targetURL: URL
        if let existingURL = card.htmlExportURL,
           fileManager.fileExists(atPath: existingURL.path) {
            targetURL = existingURL
        } else {
            do {
                let exportURL = try writePaperCardHTML(card.htmlContent, for: paper)
                card.htmlExportURL = exportURL
                targetURL = exportURL
            } catch {
                present(error)
                return
            }
        }

        NSWorkspace.shared.open(targetURL)
    }

    func fusePapers(_ papers: [Paper], settings: UserSettings) async -> PaperFusionResult? {
        guard papers.count >= FusionMaterialSelection.minimumPaperCount else {
            present(PaperFusionError.notEnoughPapers)
            return nil
        }

        guard papers.count <= FusionMaterialSelection.maximumPaperCount else {
            present(PaperFusionError.tooManyPapers(limit: FusionMaterialSelection.maximumPaperCount))
            return nil
        }

        guard let fusionGenerator else {
            present(PaperFusionError.generatorUnavailable)
            return nil
        }

        let storedAPIKey: String?
        do {
            storedAPIKey = try taggingCredentialStore.loadAPIKey()
        } catch {
            present(error)
            return nil
        }

        guard let configuration = settings.aiProviderConfiguration(apiKey: storedAPIKey) else {
            let readiness = settings.aiProviderReadiness(apiKey: storedAPIKey)
            present(PaperFusionError.providerNotConfigured(readiness.settingsMessage))
            return nil
        }

        let inputs = papers.map { paper in
            PaperFusionInput(
                paperID: paper.id,
                title: paper.title.trimmingCharacters(in: .whitespacesAndNewlines),
                authorsText: paper.authorsDisplayText,
                abstractText: truncated(paper.abstractText, limit: 1_400),
                tagNames: Array(paper.tagNames.prefix(8))
            )
        }

        do {
            let ideas = try await fusionGenerator.generateIdeas(for: inputs, configuration: configuration)
            let result = PaperFusionResult(
                selectedPaperIDs: papers.map(\.id),
                ideas: ideas,
                generatedAt: .now
            )
            showNotice("Refining complete. The reactor returned 3 research ideas.")
            return result
        } catch {
            present(error)
            return nil
        }
    }

    func hasSavedPaperStoragePassword(for settings: UserSettings) -> Bool {
        guard let endpoint = settings.paperStorageCredentialEndpoint else {
            return false
        }

        do {
            let password = try paperStorageCredentialStore.loadPassword(for: endpoint)
            return password?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        } catch {
            present(error)
            return false
        }
    }

    func savePaperStoragePassword(_ password: String, for settings: UserSettings) {
        guard let endpoint = settings.paperStorageCredentialEndpoint else {
            present(PaperStorageServiceError.invalidConfiguration("Enter the SSH host, port, and username before saving a password."))
            return
        }

        do {
            try paperStorageCredentialStore.savePassword(password, for: endpoint)
            let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
            showNotice(trimmedPassword.isEmpty ? "SSH password cleared." : "SSH password saved.")
        } catch {
            present(error)
        }
    }

    func clearPaperStoragePassword(for settings: UserSettings) {
        guard let endpoint = settings.paperStorageCredentialEndpoint else {
            return
        }

        do {
            try paperStorageCredentialStore.deletePassword(for: endpoint)
            showNotice("SSH password cleared.")
        } catch {
            present(error)
        }
    }

    func saveTaggingAPIKey(_ apiKey: String) {
        do {
            try taggingCredentialStore.saveAPIKey(apiKey)
            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            showNotice(trimmedAPIKey.isEmpty ? "AI API key cleared." : "AI API key saved.")
        } catch {
            present(error)
        }
    }

    func copyText(_ text: String, notice: String) {
        guard text.isEmpty == false else { return }
        textClipboard.setString(text)
        showNotice(notice)
    }

    @discardableResult
    func saveFeedback(
        snapshot: FeedbackSnapshot,
        submission: FeedbackSubmission,
        context: ModelContext
    ) throws -> FeedbackEntry {
        let entry = FeedbackEntry.make(snapshot: snapshot, submission: submission)
        context.insert(entry)

        do {
            try context.save()
            showNotice("Feedback saved.")
            return entry
        } catch {
            context.delete(entry)
            present(error)
            throw error
        }
    }

    func prepareReader(
        for paper: Paper,
        currentPapers: [Paper],
        settings: UserSettings,
        context: ModelContext
    ) async -> ReaderPresentation? {
        do {
            let url: URL
            if let managedLocalURL = paper.managedPDFLocalURL,
               FileManager.default.fileExists(atPath: managedLocalURL.path) {
                url = managedLocalURL
            } else if let cachedURL = paper.cachedPDFURL,
                      FileManager.default.fileExists(atPath: cachedURL.path) {
                url = cachedURL
            } else if paper.managedPDFRemoteURL != nil {
                let materializedURL = try await paperStorageService.materializeRemoteManagedPDF(
                    for: paper,
                    cacheDirectoryURL: pdfCacheService.cacheDirectoryURL
                )
                paper.cachedPDFURL = materializedURL
                try persistAndSync(allPapers: currentPapers, settings: settings, context: context)
                url = materializedURL
            } else {
                url = try await pdfCacheService.cachePDF(for: paper)
                try persistAndSync(allPapers: currentPapers, settings: settings, context: context)
            }
            return ReaderPresentation(paperID: paper.id, title: paper.title, fileURL: url)
        } catch {
            present(error)
            return nil
        }
    }

    func openSource(for paper: Paper) {
        guard let sourceURL = paper.sourceURL else { return }
        NSWorkspace.shared.open(sourceURL)
    }

    func delete(
        paper: Paper,
        allPapers: [Paper],
        settings: UserSettings,
        context: ModelContext
    ) async {
        do {
            try pdfCacheService.removeCachedPDF(for: paper)
        } catch {
            present(error)
            return
        }

        if paper.managedPDFLocalURL != nil || paper.managedPDFRemoteURL != nil {
            try? await paperStorageService.removeManagedPDF(for: paper)
        }

        do {
            context.delete(paper)
            let remaining = allPapers.filter { $0.id != paper.id }
            try persistAndSync(allPapers: remaining, settings: settings, context: context)
        } catch {
            present(error)
        }
    }

    func clearPresentedError() {
        presentedError = nil
    }

    func showNotice(_ message: String) {
        noticeDismissTask?.cancel()
        let notice = PresentedNotice(message: message)
        presentedNotice = notice

        noticeDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard Task.isCancelled == false else { return }
            guard self?.presentedNotice?.id == notice.id else { return }
            self?.presentedNotice = nil
        }
    }

    private func persistAndSync(
        allPapers: [Paper],
        settings: UserSettings,
        context: ModelContext,
        referenceDate: Date = .now
    ) throws {
        schedulerService.applySchedule(
            to: allPapers,
            papersPerDay: settings.papersPerDay,
            referenceDate: referenceDate
        )
        try context.save()
        Task { @MainActor in
            await reminderService.syncNotifications(for: allPapers, settings: settings)
        }
    }

    private func queuedPapers(from papers: [Paper]) -> [Paper] {
        papers
            .filter { $0.status.isActiveQueue }
            .sorted(by: queueSort)
    }

    private func nextQueuePosition(in papers: [Paper]) -> Int {
        queuedPapers(from: papers).count
    }

    private func resolveTags(from tagString: String) -> [Tag] {
        Tag.buildList(
            from: tagString
                .split(separator: ",")
                .map(String.init)
        )
    }

    private func replaceTags(for paper: Paper, with tags: [Tag], in context: ModelContext) {
        let previousTags = paper.tags
        paper.tags = tags
        for previousTag in previousTags {
            context.delete(previousTag)
        }
    }

    private func present(_ error: Error) {
        presentedError = PresentedError(message: error.localizedDescription)
    }

    private func updateImportStatus(_ message: String) {
        importStatusDismissTask?.cancel()
        importStatusMessage = message
    }

    private func completeImportStatus(_ message: String) {
        updateImportStatus(message)
        dismissImportStatus(after: 1_500_000_000)
    }

    private func failImportStatus(_ message: String) {
        updateImportStatus(message)
        dismissImportStatus(after: 2_500_000_000)
    }

    private func dismissImportStatus(after nanoseconds: UInt64) {
        importStatusDismissTask?.cancel()
        let message = importStatusMessage
        importStatusDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard Task.isCancelled == false else { return }
            guard self?.importStatusMessage == message else { return }
            self?.importStatusMessage = nil
        }
    }

    private func writePaperCardHTML(_ htmlContent: String, for paper: Paper) throws -> URL {
        try fileManager.createDirectory(at: paperCardHTMLDirectoryURL, withIntermediateDirectories: true)
        let sanitizedTitle = paperStorageService.managedFilename(paperID: paper.id, title: paper.title)
            .replacingOccurrences(of: ".pdf", with: ".html")
        let exportURL = paperCardHTMLDirectoryURL.appendingPathComponent(sanitizedTitle)
        try htmlContent.write(to: exportURL, atomically: true, encoding: .utf8)
        return exportURL
    }

    private func combinedNoticeMessages(_ first: String?, _ second: String?) -> String? {
        let messages = [first, second]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard messages.isEmpty == false else { return nil }
        return messages.joined(separator: "\n")
    }

    private func truncated(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func storeManagedPDFIfPossible(for paper: Paper, settings: UserSettings) async -> String? {
        guard paper.pdfURL != nil else {
            return nil
        }

        do {
            let location = try await paperStorageService.storeManagedPDF(for: paper, settings: settings)
            switch location {
            case let .local(url):
                paper.managedPDFLocalURL = url
                paper.managedPDFRemoteURL = nil
            case let .remote(url):
                paper.managedPDFLocalURL = nil
                paper.managedPDFRemoteURL = url
            }
            return nil
        } catch {
            paper.managedPDFLocalURL = nil
            paper.managedPDFRemoteURL = nil
            return "Managed PDF storage failed. Imported the paper without a stored PDF copy. \(error.localizedDescription)"
        }
    }

    private func storeManagedLocalPDFIfPossible(
        for paper: Paper,
        sourceFileURL: URL,
        settings: UserSettings
    ) async -> String? {
        do {
            let location = try await paperStorageService.storeManagedLocalPDF(
                from: sourceFileURL,
                for: paper,
                settings: settings
            )
            switch location {
            case let .local(url):
                paper.managedPDFLocalURL = url
                paper.managedPDFRemoteURL = nil
                paper.sourceURL = url
                paper.pdfURL = url
            case let .remote(url):
                paper.managedPDFLocalURL = nil
                paper.managedPDFRemoteURL = url
            }
            return nil
        } catch {
            paper.managedPDFLocalURL = nil
            paper.managedPDFRemoteURL = nil
            return "Managed PDF storage failed. Imported the paper without a stored PDF copy. \(error.localizedDescription)"
        }
    }

    private func runStorageFolderMonitoring(context: ModelContext) async {
        while Task.isCancelled == false {
            guard let settings = (try? context.fetch(FetchDescriptor<UserSettings>()).first) else {
                monitoredImportDirectorySignature = nil
                return
            }

            let papers = (try? context.fetch(FetchDescriptor<Paper>())) ?? []
            let monitoredSources = monitoredImportSources(for: settings)
            if monitoredSources.isEmpty {
                monitoredImportDirectorySignature = nil
                return
            }

            for source in monitoredSources {
                let outcomes = await importLocalPDFs(
                    at: discoverImportablePDFs(in: source.directoryURL, currentPapers: papers),
                    settings: settings,
                    currentPapers: papers,
                    in: context,
                    origin: source.origin
                )

                let importedCount = outcomes.filter(\.didCreatePaper).count
                if importedCount > 0 {
                    let noun = importedCount == 1 ? "paper" : "papers"
                    showNotice("Imported \(importedCount) \(noun) from \(source.noticeLabel).")
                }
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func importLocalPDFs(
        at fileURLs: [URL],
        settings: UserSettings,
        currentPapers: [Paper],
        in context: ModelContext,
        origin: LocalPDFImportOrigin
    ) async -> [PaperImportResult] {
        var outcomes: [PaperImportResult] = []
        let uniqueFileURLs = Array(Set(fileURLs.map(\.standardizedFileURL))).sorted(by: { $0.path < $1.path })

        for (index, fileURL) in uniqueFileURLs.enumerated() {
            if origin == .drop {
                updateImportStatus(
                    "Importing PDF \(index + 1)/\(uniqueFileURLs.count): \(fileURL.lastPathComponent)"
                )
            }

            let path = fileURL.path
            guard activeLocalImportPaths.contains(path) == false else { continue }
            activeLocalImportPaths.insert(path)
            defer { activeLocalImportPaths.remove(path) }

            do {
                let result = try await importService.createPaper(
                    from: PaperCaptureRequest(sourceFileURL: fileURL),
                    settings: settings,
                    in: context
                )

                if result.didCreatePaper {
                    let paper = result.paper
                    let existingPapers = (try? context.fetch(FetchDescriptor<Paper>())) ?? currentPapers
                    let papersExcludingImported = existingPapers.filter { $0.id != paper.id }
                    paper.manualDueDateOverride = nil
                    if paper.status.isActiveQueue {
                        paper.queuePosition = nextQueuePosition(in: papersExcludingImported)
                    }

                    let _ = await storeManagedLocalPDFIfPossible(for: paper, sourceFileURL: fileURL, settings: settings)
                    try persistAndSync(
                        allPapers: papersExcludingImported + [paper],
                        settings: settings,
                        context: context
                    )
                }

                cleanupImportedSourceIfNeeded(fileURL: fileURL, result: result, origin: origin)
                outcomes.append(result)
            } catch {
                if origin == .drop {
                    present(error)
                }
            }
        }

        refreshStorageFolderMonitoring(context: context)
        return outcomes
    }

    private func discoverImportablePDFs(in directoryURL: URL, currentPapers: [Paper]) -> [URL] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return []
        }

        let trackedPaths = Set(
            currentPapers.flatMap { paper in
                [
                    paper.sourceURL?.isFileURL == true ? paper.sourceURL?.standardizedFileURL.path : nil,
                    paper.pdfURL?.isFileURL == true ? paper.pdfURL?.standardizedFileURL.path : nil,
                    paper.managedPDFLocalURL?.standardizedFileURL.path
                ].compactMap { $0 }
            }
        )

        let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var discovered: [URL] = []
        while let nextURL = enumerator?.nextObject() as? URL {
            guard nextURL.pathExtension.lowercased() == "pdf" else { continue }
            guard trackedPaths.contains(nextURL.standardizedFileURL.path) == false else { continue }
            discovered.append(nextURL)
        }
        return discovered
    }

    private func monitoredStorageFolderURL(for settings: UserSettings) -> URL? {
        switch settings.paperStorageMode {
        case .defaultLocal:
            return defaultPaperStorageDirectoryURL
        case .customLocal:
            let trimmedPath = settings.customPaperStoragePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedPath.isEmpty == false else { return nil }
            return URL(fileURLWithPath: trimmedPath, isDirectory: true)
        case .remoteSSH:
            return nil
        }
    }

    private func monitoredImportSources(for settings: UserSettings) -> [MonitoredImportSource] {
        var sources: [MonitoredImportSource] = []

        if settings.paperStorageMode != .remoteSSH {
            sources.append(
                MonitoredImportSource(
                    directoryURL: agentImportDirectoryURL,
                    origin: .agentInbox,
                    noticeLabel: "the agent import inbox"
                )
            )
        }

        if let directoryURL = monitoredStorageFolderURL(for: settings),
           sources.contains(where: { $0.directoryURL.standardizedFileURL == directoryURL.standardizedFileURL }) == false {
            sources.append(
                MonitoredImportSource(
                    directoryURL: directoryURL,
                    origin: .storageFolderScan,
                    noticeLabel: "the storage folder"
                )
            )
        }

        return sources
    }

    private func monitoredImportDirectorySignature(for settings: UserSettings) -> String? {
        let paths = monitoredImportSources(for: settings)
            .map { $0.directoryURL.standardizedFileURL.path }
            .sorted()
        guard paths.isEmpty == false else { return nil }
        return paths.joined(separator: "\n")
    }

    private func cleanupImportedSourceIfNeeded(
        fileURL: URL,
        result: PaperImportResult,
        origin: LocalPDFImportOrigin
    ) {
        guard origin == .agentInbox else { return }
        if result.paper.managedPDFLocalURL?.standardizedFileURL == fileURL.standardizedFileURL {
            return
        }
        guard result.notice == "That paper is already in your library." || result.paper.managedPDFLocalURL != nil else { return }

        try? fileManager.removeItem(at: fileURL)
    }

    private func queueSort(lhs: Paper, rhs: Paper) -> Bool {
        if lhs.queuePosition != rhs.queuePosition {
            return lhs.queuePosition < rhs.queuePosition
        }
        return lhs.dateAdded < rhs.dateAdded
    }
}

private enum LocalPDFImportOrigin {
    case drop
    case storageFolderScan
    case agentInbox
}

private struct MonitoredImportSource {
    let directoryURL: URL
    let origin: LocalPDFImportOrigin
    let noticeLabel: String
}
