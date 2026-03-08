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

    init(metadataResolver: MetadataResolving) {
        self.metadataResolver = metadataResolver
    }

    func createPaper(
        from request: PaperCaptureRequest,
        settings: UserSettings,
        in context: ModelContext,
        now: Date = .now
    ) async throws -> Paper {
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
        paper.tags = try resolveTags(named: request.tagNames, in: context)
        context.insert(paper)
        return paper
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
