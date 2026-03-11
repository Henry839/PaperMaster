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
    let readerAnswerer: ReaderAnswerGenerating?
    let schedulerService: SchedulerService
    let pdfCacheService: PDFCacheService
    let paperStorageService: PaperStorageService
    let reminderService: ReminderService
    let taggingCredentialStore: TaggingCredentialStoring
    let paperStorageCredentialStore: PaperStorageCredentialStoring
    let readerDocumentContextLoader: ReaderDocumentContextLoading
    let textClipboard: TextClipboardWriting
    @ObservationIgnored private let startupNoticeMessage: String?
    @ObservationIgnored private let startupErrorMessage: String?
    @ObservationIgnored private var noticeDismissTask: Task<Void, Never>?
    private(set) var didBootstrap = false
    var presentedError: PresentedError?
    var presentedNotice: PresentedNotice?

    init(
        importService: PaperImportService,
        fusionGenerator: PaperFusionGenerating? = nil,
        readerAnswerer: ReaderAnswerGenerating? = nil,
        schedulerService: SchedulerService = SchedulerService(),
        pdfCacheService: PDFCacheService = PDFCacheService(),
        paperStorageService: PaperStorageService = PaperStorageService(),
        reminderService: ReminderService = ReminderService(),
        taggingCredentialStore: TaggingCredentialStoring = InMemoryTaggingCredentialStore(),
        paperStorageCredentialStore: PaperStorageCredentialStoring = InMemoryPaperStorageCredentialStore(),
        readerDocumentContextLoader: ReaderDocumentContextLoading = PDFKitReaderDocumentContextLoader(),
        textClipboard: TextClipboardWriting = SystemTextClipboardWriter(),
        startupNoticeMessage: String? = nil,
        startupErrorMessage: String? = nil
    ) {
        self.importService = importService
        self.fusionGenerator = fusionGenerator
        self.readerAnswerer = readerAnswerer
        self.schedulerService = schedulerService
        self.pdfCacheService = pdfCacheService
        self.paperStorageService = paperStorageService
        self.reminderService = reminderService
        self.taggingCredentialStore = taggingCredentialStore
        self.paperStorageCredentialStore = paperStorageCredentialStore
        self.readerDocumentContextLoader = readerDocumentContextLoader
        self.textClipboard = textClipboard
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
            readerAnswerer: OpenAICompatibleReaderAnswerer(),
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
        await reminderService.syncNotifications(for: papers, settings: settings)
        if let startupErrorMessage {
            presentedError = PresentedError(message: startupErrorMessage)
        } else if let startupNoticeMessage {
            showNotice(startupNoticeMessage)
        }
        didBootstrap = true
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
        do {
            let result = try await importService.createPaper(from: request, settings: settings, in: context)
            let paper = result.paper
            if result.didCreatePaper == false {
                if let notice = result.notice {
                    showNotice(notice)
                }
                return paper
            }
            paper.manualDueDateOverride = nil
            if paper.status.isActiveQueue {
                paper.queuePosition = nextQueuePosition(in: currentPapers + [paper])
            }
            let storageNotice = await storeManagedPDFIfPossible(for: paper, settings: settings)
            try persistAndSync(allPapers: currentPapers + [paper], settings: settings, context: context)
            if let notice = combinedNoticeMessages(result.notice, storageNotice) {
                showNotice(notice)
            }
            return paper
        } catch {
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

    private func persistAndSync(allPapers: [Paper], settings: UserSettings, context: ModelContext) throws {
        schedulerService.applySchedule(to: allPapers, papersPerDay: settings.papersPerDay)
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

    private func queueSort(lhs: Paper, rhs: Paper) -> Bool {
        if lhs.queuePosition != rhs.queuePosition {
            return lhs.queuePosition < rhs.queuePosition
        }
        return lhs.dateAdded < rhs.dateAdded
    }
}
