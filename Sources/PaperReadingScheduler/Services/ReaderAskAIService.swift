import Foundation
import PDFKit

struct ReaderAskAIInput: Sendable {
    let question: String
    let quotedText: String
    let pageNumber: Int
    let paperTitle: String
    let authorsText: String
    let abstractText: String
    let tagNames: [String]
    let documentText: String
    let documentWasTruncated: Bool
}

protocol ReaderAnswerGenerating: Sendable {
    func answerQuestion(
        for input: ReaderAskAIInput,
        configuration: AIProviderConfiguration
    ) async throws -> String
}

protocol ReaderDocumentContextLoading: Sendable {
    func loadDocumentContext(from fileURL: URL) -> ReaderAskAIDocumentContext
}

struct PDFKitReaderDocumentContextLoader: ReaderDocumentContextLoading {
    func loadDocumentContext(from fileURL: URL) -> ReaderAskAIDocumentContext {
        guard let document = PDFDocument(url: fileURL) else {
            return .empty
        }

        return ReaderAskAIDocumentContext.make(from: document.string ?? "")
    }
}

enum ReaderAnswerError: LocalizedError, Equatable {
    case generatorUnavailable
    case providerNotConfigured(String)
    case invalidEndpoint
    case invalidResponse
    case providerError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .generatorUnavailable:
            return "Ask AI is not available in this build."
        case let .providerNotConfigured(message):
            return message
        case .invalidEndpoint:
            return "The Ask AI endpoint is invalid."
        case .invalidResponse:
            return "Ask AI returned an invalid response."
        case let .providerError(statusCode, message):
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedMessage.isEmpty
                ? "Ask AI failed with status \(statusCode)."
                : "Ask AI failed with status \(statusCode): \(trimmedMessage)"
        }
    }
}

struct OpenAICompatibleReaderAnswerer: ReaderAnswerGenerating {
    let networking: HTTPNetworking
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    init(
        networking: HTTPNetworking = URLSessionHTTPNetworking(),
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.networking = networking
        self.decoder = decoder
        self.encoder = encoder
    }

    func answerQuestion(
        for input: ReaderAskAIInput,
        configuration: AIProviderConfiguration
    ) async throws -> String {
        guard let endpoint = makeOpenAIChatCompletionsEndpoint(from: configuration.baseURL) else {
            throw ReaderAnswerError.invalidEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(
            OpenAIChatCompletionsRequest(
                model: configuration.model,
                temperature: 0.2,
                messages: [
                    .init(role: "system", content: systemPrompt),
                    .init(role: "user", content: makeUserPrompt(from: input))
                ]
            )
        )

        let (data, response) = try await networking.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReaderAnswerError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let providerMessage = (try? decoder.decode(OpenAIErrorResponse.self, from: data).error.message) ?? ""
            throw ReaderAnswerError.providerError(statusCode: httpResponse.statusCode, message: providerMessage)
        }

        let payload = try decoder.decode(OpenAIChatCompletionsResponse.self, from: data)
        guard let content = payload.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              content.isEmpty == false else {
            throw ReaderAnswerError.invalidResponse
        }

        return content
    }

    private func makeUserPrompt(from input: ReaderAskAIInput) -> String {
        let abstract = input.abstractText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = input.tagNames.isEmpty ? "None" : input.tagNames.joined(separator: ", ")
        let documentText = input.documentText.isEmpty ? "Unavailable" : input.documentText

        return """
        Answer the user's question about a selected passage from an academic paper.
        Ground the answer in the quoted passage and supplied paper context.
        Be concise, specific, and do not invent claims not supported by the provided material.

        User question: \(input.question)
        Selected passage (page \(input.pageNumber)): \(input.quotedText)
        Paper title: \(input.paperTitle)
        Authors: \(input.authorsText)
        Tags: \(tags)
        Abstract: \(abstract.isEmpty ? "None" : abstract)
        Document context truncated: \(input.documentWasTruncated ? "true" : "false")
        Full document text: \(documentText)
        """
    }

    private var systemPrompt: String {
        """
        You help a researcher understand passages from academic papers.
        Answer directly in plain text, explain the passage in context, and call out uncertainty when the provided context is incomplete.
        """
    }
}
