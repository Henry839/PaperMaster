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
    let schedulerService: SchedulerService
    let pdfCacheService: PDFCacheService
    let reminderService: ReminderService
    let taggingCredentialStore: TaggingCredentialStoring
    let textClipboard: TextClipboardWriting
    @ObservationIgnored private var noticeDismissTask: Task<Void, Never>?
    private(set) var didBootstrap = false
    var presentedError: PresentedError?
    var presentedNotice: PresentedNotice?

    init(
        importService: PaperImportService,
        schedulerService: SchedulerService = SchedulerService(),
        pdfCacheService: PDFCacheService = PDFCacheService(),
        reminderService: ReminderService = ReminderService(),
        taggingCredentialStore: TaggingCredentialStoring = InMemoryTaggingCredentialStore(),
        textClipboard: TextClipboardWriting = SystemTextClipboardWriter()
    ) {
        self.importService = importService
        self.schedulerService = schedulerService
        self.pdfCacheService = pdfCacheService
        self.reminderService = reminderService
        self.taggingCredentialStore = taggingCredentialStore
        self.textClipboard = textClipboard
    }

    static func live() -> AppServices {
        let resolver = MetadataResolver()
        let credentialStore = KeychainTaggingCredentialStore()
        return AppServices(
            importService: PaperImportService(
                metadataResolver: resolver,
                publicationEnricher: CrossrefPublicationEnricher(),
                tagGenerator: OpenAICompatiblePaperTagger(),
                credentialStore: credentialStore
            ),
            taggingCredentialStore: credentialStore
        )
    }

    func bootstrap(in context: ModelContext, settings existingSettings: [UserSettings], papers: [Paper]) async {
        let settings = ensureSettings(in: context, existingSettings: existingSettings)
        guard didBootstrap == false else { return }

        await reminderService.requestAuthorization()
        schedulerService.applySchedule(to: papers, papersPerDay: settings.papersPerDay)
        try? context.save()
        await reminderService.syncNotifications(for: papers, settings: settings)
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
            if settings.autoCachePDFs, paper.pdfURL != nil {
                _ = try? await pdfCacheService.cachePDF(for: paper)
            }
            try persistAndSync(allPapers: currentPapers + [paper], settings: settings, context: context)
            if let notice = result.notice {
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
            paper.tags = try resolveTags(from: tagString, in: context)
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

    func loadTaggingAPIKey() -> String {
        do {
            return try taggingCredentialStore.loadAPIKey() ?? ""
        } catch {
            present(error)
            return ""
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
            if let cachedURL = paper.cachedPDFURL {
                url = cachedURL
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
    ) {
        do {
            try pdfCacheService.removeCachedPDF(for: paper)
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

    private func resolveTags(from tagString: String, in context: ModelContext) throws -> [Tag] {
        let normalizedNames = Array(
            Set(
                tagString
                    .split(separator: ",")
                    .map { Tag.normalize(String($0)) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()

        guard normalizedNames.isEmpty == false else { return [] }

        let existing = try context.fetch(FetchDescriptor<Tag>())
        var tagsByName = Dictionary(uniqueKeysWithValues: existing.map { ($0.name, $0) })
        var resolved: [Tag] = []

        for name in normalizedNames {
            if let tag = tagsByName[name] {
                resolved.append(tag)
            } else {
                let tag = Tag(name: name)
                context.insert(tag)
                tagsByName[name] = tag
                resolved.append(tag)
            }
        }

        return resolved
    }

    private func present(_ error: Error) {
        presentedError = PresentedError(message: error.localizedDescription)
    }

    private func queueSort(lhs: Paper, rhs: Paper) -> Bool {
        if lhs.queuePosition != rhs.queuePosition {
            return lhs.queuePosition < rhs.queuePosition
        }
        return lhs.dateAdded < rhs.dateAdded
    }
}
