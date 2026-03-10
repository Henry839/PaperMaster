import Foundation

struct ReaderAskAIDocumentContext: Equatable, Sendable {
    static let maximumDocumentLength = 20_000
    static let empty = ReaderAskAIDocumentContext(documentText: "", documentWasTruncated: false)

    let documentText: String
    let documentWasTruncated: Bool

    var hasUsableText: Bool {
        documentText.isEmpty == false
    }

    static func make(from rawText: String, limit: Int = maximumDocumentLength) -> ReaderAskAIDocumentContext {
        let normalizedText = rawText.normalizedReaderContent
        guard normalizedText.isEmpty == false else {
            return .empty
        }

        guard normalizedText.count > limit else {
            return ReaderAskAIDocumentContext(
                documentText: normalizedText,
                documentWasTruncated: false
            )
        }

        let endIndex = normalizedText.index(normalizedText.startIndex, offsetBy: limit)
        return ReaderAskAIDocumentContext(
            documentText: String(normalizedText[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines),
            documentWasTruncated: true
        )
    }
}

struct ReaderAskAIDraft: Equatable, Sendable {
    static let defaultQuestion = "Explain this passage in the context of the paper and why it matters."

    let selection: ReaderSelectionSnapshot
    var question: String

    init(selection: ReaderSelectionSnapshot, question: String = defaultQuestion) {
        self.selection = selection
        self.question = question
    }

    var trimmedQuestion: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ReaderAskAIExchange: Identifiable, Equatable, Sendable {
    let id: UUID
    let quotedText: String
    let pageNumber: Int
    let question: String
    let answer: String
    let askedAt: Date

    init(
        id: UUID = UUID(),
        quotedText: String,
        pageNumber: Int,
        question: String,
        answer: String,
        askedAt: Date = .now
    ) {
        self.id = id
        self.quotedText = quotedText.normalizedReaderContent
        self.pageNumber = pageNumber
        self.question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        self.answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        self.askedAt = askedAt
    }
}

struct ReaderAskAISessionState: Equatable {
    var draft: ReaderAskAIDraft?
    var exchanges: [ReaderAskAIExchange] = []
    var isAwaitingResponse = false

    var canSubmit: Bool {
        guard let draft else { return false }
        return draft.trimmedQuestion.isEmpty == false && isAwaitingResponse == false
    }

    mutating func capture(selection: ReaderSelectionSnapshot) {
        guard draft?.selection != selection else { return }
        draft = ReaderAskAIDraft(selection: selection)
    }

    mutating func updateQuestion(_ question: String) {
        guard draft != nil else { return }
        draft?.question = question
    }

    mutating func beginRequest() -> ReaderAskAIDraft? {
        guard let draft, isAwaitingResponse == false else {
            return nil
        }

        let trimmedQuestion = draft.trimmedQuestion
        guard trimmedQuestion.isEmpty == false else {
            return nil
        }

        let normalizedDraft = ReaderAskAIDraft(selection: draft.selection, question: trimmedQuestion)
        self.draft = normalizedDraft
        isAwaitingResponse = true
        return normalizedDraft
    }

    mutating func finishRequest(with draft: ReaderAskAIDraft, answer: String, askedAt: Date = .now) {
        isAwaitingResponse = false
        exchanges.insert(
            ReaderAskAIExchange(
                quotedText: draft.selection.quotedText,
                pageNumber: draft.selection.pageNumber,
                question: draft.trimmedQuestion,
                answer: answer,
                askedAt: askedAt
            ),
            at: 0
        )
    }

    mutating func failRequest() {
        isAwaitingResponse = false
    }

    mutating func clearDraft() {
        draft = nil
    }

    mutating func reset() {
        self = ReaderAskAISessionState()
    }
}

extension ReaderSelectionSnapshot {
    var pageNumber: Int {
        pageIndex + 1
    }
}

extension String {
    var normalizedReaderContent: String {
        split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
