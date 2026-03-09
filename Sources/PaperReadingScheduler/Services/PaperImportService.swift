import Foundation
import SwiftData

struct PaperCaptureRequest: Sendable {
    var sourceText: String
    var manualTitle: String
    var manualAuthors: String
    var manualAbstract: String
    var tagNames: [String]
    var preferredBehavior: ImportBehavior?

    init(
        sourceText: String = "",
        manualTitle: String = "",
        manualAuthors: String = "",
        manualAbstract: String = "",
        tagNames: [String] = [],
        preferredBehavior: ImportBehavior? = nil
    ) {
        self.sourceText = sourceText
        self.manualTitle = manualTitle
        self.manualAuthors = manualAuthors
        self.manualAbstract = manualAbstract
        self.tagNames = tagNames
        self.preferredBehavior = preferredBehavior
    }

    var sourceURL: URL? {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    var parsedManualAuthors: [String] {
        manualAuthors
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct PaperImportResult {
    let paper: Paper
    let notice: String?
}

enum PaperImportError: LocalizedError {
    case invalidSourceURL
    case missingTitle

    var errorDescription: String? {
        switch self {
        case .invalidSourceURL:
            "Enter a valid paper URL or direct PDF link."
        case .missingTitle:
            "A title is required when metadata could not be inferred."
        }
    }
}

@MainActor
struct PaperImportService {
    let metadataResolver: MetadataResolving
    let tagGenerator: PaperTagGenerating?
    let credentialStore: TaggingCredentialStoring

    init(
        metadataResolver: MetadataResolving,
        tagGenerator: PaperTagGenerating? = nil,
        credentialStore: TaggingCredentialStoring = InMemoryTaggingCredentialStore()
    ) {
        self.metadataResolver = metadataResolver
        self.tagGenerator = tagGenerator
        self.credentialStore = credentialStore
    }

    func createPaper(
        from request: PaperCaptureRequest,
        settings: UserSettings,
        in context: ModelContext,
        now: Date = .now
    ) async throws -> PaperImportResult {
        var draft = PaperDraft()

        if let sourceURL = request.sourceURL {
            guard sourceURL.scheme?.hasPrefix("http") == true else {
                throw PaperImportError.invalidSourceURL
            }
            draft.apply(resolved: try await metadataResolver.resolve(url: sourceURL))
        }

        draft.applyManualOverrides(from: request)
        draft.applySourceFallback(from: request.sourceURL)

        guard !draft.title.isEmpty else {
            throw PaperImportError.missingTitle
        }

        let status = (request.preferredBehavior ?? settings.defaultImportBehavior) == .scheduleImmediately ? PaperStatus.scheduled : .inbox
        let autoTaggingOutcome = await generateAutomaticTags(for: draft, settings: settings, in: context)
        let paper = Paper(
            title: draft.title,
            authors: draft.authors,
            abstractText: draft.abstractText,
            sourceURL: draft.sourceURL,
            pdfURL: draft.pdfURL,
            status: status,
            queuePosition: 0,
            dateAdded: now,
            notes: ""
        )
        let resolvedTagNames = Array(Set(request.tagNames + autoTaggingOutcome.tagNames)).sorted()
        paper.tags = try resolveTags(named: resolvedTagNames, in: context)
        context.insert(paper)
        return PaperImportResult(paper: paper, notice: autoTaggingOutcome.notice)
    }

    func updatePaper(
        _ paper: Paper,
        with request: PaperCaptureRequest,
        in context: ModelContext
    ) async throws {
        var draft = PaperDraft(
            title: paper.title,
            authors: paper.authors,
            abstractText: paper.abstractText,
            sourceURL: paper.sourceURL,
            pdfURL: paper.pdfURL
        )

        if let sourceURL = request.sourceURL {
            guard sourceURL.scheme?.hasPrefix("http") == true else {
                throw PaperImportError.invalidSourceURL
            }
            draft.apply(resolved: try await metadataResolver.resolve(url: sourceURL))
        }

        draft.applyManualOverrides(from: request)
        draft.applySourceFallback(from: request.sourceURL)

        guard !draft.title.isEmpty else {
            throw PaperImportError.missingTitle
        }

        paper.title = draft.title
        paper.authors = draft.authors
        paper.abstractText = draft.abstractText
        paper.sourceURL = draft.sourceURL
        paper.pdfURL = draft.pdfURL
        paper.tags = try resolveTags(named: request.tagNames, in: context)
    }

    private func resolveTags(named names: [String], in context: ModelContext) throws -> [Tag] {
        let normalizedNames = Array(Set(names.map(Tag.normalize).filter { !$0.isEmpty })).sorted()
        guard !normalizedNames.isEmpty else { return [] }

        let existing = try context.fetch(FetchDescriptor<Tag>())
        var tagsByName = Dictionary(uniqueKeysWithValues: existing.map { ($0.name, $0) })
        var resolved: [Tag] = []

        for name in normalizedNames {
            if let existingTag = tagsByName[name] {
                resolved.append(existingTag)
            } else {
                let newTag = Tag(name: name)
                context.insert(newTag)
                tagsByName[name] = newTag
                resolved.append(newTag)
            }
        }

        return resolved
    }

    private func generateAutomaticTags(
        for draft: PaperDraft,
        settings: UserSettings,
        in context: ModelContext
    ) async -> AutoTaggingOutcome {
        guard settings.aiTaggingEnabled else {
            return AutoTaggingOutcome()
        }

        let storedAPIKey: String?
        do {
            storedAPIKey = try credentialStore.loadAPIKey()
        } catch {
            return AutoTaggingOutcome(
                notice: "AI auto-tagging could not access the saved API key. Imported without generated tags."
            )
        }

        let readiness = settings.aiTaggingReadiness(apiKey: storedAPIKey)

        switch readiness {
        case .disabled:
            return AutoTaggingOutcome()
        case let .ready(configuration):
            guard let tagGenerator else {
                return AutoTaggingOutcome(
                    notice: "AI auto-tagging is enabled but not available. Imported without generated tags."
                )
            }

            let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedAbstract = draft.abstractText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedTitle.isEmpty == false || trimmedAbstract.isEmpty == false else {
                return AutoTaggingOutcome()
            }

            do {
                let existingTags = try context.fetch(FetchDescriptor<Tag>()).map(\.name).sorted()
                let generatedTags = try await tagGenerator.generateTags(
                    for: PaperTaggingInput(
                        title: trimmedTitle,
                        abstractText: trimmedAbstract,
                        existingTags: existingTags
                    ),
                    configuration: configuration
                )
                return AutoTaggingOutcome(tagNames: generatedTags)
            } catch {
                return AutoTaggingOutcome(
                    notice: "AI auto-tagging failed. Imported without generated tags."
                )
            }
        case .missingBaseURL, .invalidBaseURL, .missingModel, .missingAPIKey:
            return AutoTaggingOutcome(notice: readiness.importNotice)
        }
    }
}

private struct PaperDraft {
    var title: String = ""
    var authors: [String] = []
    var abstractText: String = ""
    var sourceURL: URL?
    var pdfURL: URL?

    init(
        title: String = "",
        authors: [String] = [],
        abstractText: String = "",
        sourceURL: URL? = nil,
        pdfURL: URL? = nil
    ) {
        self.title = title
        self.authors = authors
        self.abstractText = abstractText
        self.sourceURL = sourceURL
        self.pdfURL = pdfURL
    }

    mutating func apply(resolved: ResolvedPaperMetadata) {
        title = resolved.title
        authors = resolved.authors
        abstractText = resolved.abstractText
        sourceURL = resolved.sourceURL
        pdfURL = resolved.pdfURL
    }

    mutating func applyManualOverrides(from request: PaperCaptureRequest) {
        let manualTitle = request.manualTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manualTitle.isEmpty {
            title = manualTitle
        }

        let manualAuthors = request.parsedManualAuthors
        if !manualAuthors.isEmpty {
            authors = manualAuthors
        }

        let manualAbstract = request.manualAbstract.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manualAbstract.isEmpty {
            abstractText = manualAbstract
        }

        if sourceURL == nil {
            sourceURL = request.sourceURL
        }

        if pdfURL == nil, request.sourceURL?.pathExtension.lowercased() == "pdf" {
            pdfURL = request.sourceURL
        }
    }

    mutating func applySourceFallback(from sourceURL: URL?) {
        guard let sourceURL else { return }

        if title.isEmpty {
            let filename = sourceURL.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? sourceURL.lastPathComponent
            title = filename
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if self.sourceURL == nil {
            self.sourceURL = sourceURL
        }

        if pdfURL == nil, sourceURL.pathExtension.lowercased() == "pdf" {
            pdfURL = sourceURL
        }
    }
}

private struct AutoTaggingOutcome {
    var tagNames: [String] = []
    var notice: String? = nil
}

struct InMemoryTaggingCredentialStore: TaggingCredentialStoring {
    func loadAPIKey() throws -> String? { nil }
    func saveAPIKey(_ apiKey: String) throws {}
    func deleteAPIKey() throws {}
}
