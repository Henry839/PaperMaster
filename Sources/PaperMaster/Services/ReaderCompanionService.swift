import Foundation

struct ReaderCompanionInput: Sendable {
    let focusPassage: ReaderFocusPassageSnapshot
    let paperTitle: String
    let authorsText: String
    let abstractText: String
    let tagNames: [String]
    let documentText: String
    let documentWasTruncated: Bool
    let recentComments: [ReaderElfComment]
}

struct ReaderCompanionOutput: Equatable, Sendable {
    let shouldInterrupt: Bool
    let mood: ReaderElfMood
    let comment: String
}

protocol ReaderCompanionGenerating: Sendable {
    func generateComment(
        for input: ReaderCompanionInput,
        configuration: AIProviderConfiguration
    ) async throws -> ReaderCompanionOutput
}

enum ReaderCompanionError: LocalizedError, Equatable {
    case generatorUnavailable
    case providerNotConfigured(String)
    case invalidEndpoint
    case invalidResponse
    case providerError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .generatorUnavailable:
            return "The reader elf is not available in this build."
        case let .providerNotConfigured(message):
            return message
        case .invalidEndpoint:
            return "The reader elf endpoint is invalid."
        case .invalidResponse:
            return "The reader elf returned an invalid response."
        case let .providerError(statusCode, message):
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedMessage.isEmpty
                ? "The reader elf failed with status \(statusCode)."
                : "The reader elf failed with status \(statusCode): \(trimmedMessage)"
        }
    }
}

struct OpenAICompatibleReaderCompanionGenerator: ReaderCompanionGenerating {
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

    func generateComment(
        for input: ReaderCompanionInput,
        configuration: AIProviderConfiguration
    ) async throws -> ReaderCompanionOutput {
        guard let endpoint = makeOpenAIChatCompletionsEndpoint(from: configuration.baseURL) else {
            throw ReaderCompanionError.invalidEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(
            OpenAIChatCompletionsRequest(
                model: configuration.model,
                temperature: 0.55,
                messages: [
                    .init(role: "system", content: systemPrompt),
                    .init(role: "user", content: makeUserPrompt(from: input))
                ]
            )
        )

        let (data, response) = try await networking.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReaderCompanionError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let providerMessage = (try? decoder.decode(OpenAIErrorResponse.self, from: data).error.message) ?? ""
            throw ReaderCompanionError.providerError(statusCode: httpResponse.statusCode, message: providerMessage)
        }

        let payload = try decoder.decode(OpenAIChatCompletionsResponse.self, from: data)
        guard let content = payload.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              content.isEmpty == false else {
            throw ReaderCompanionError.invalidResponse
        }

        return try parseOutput(from: content)
    }

    private func makeUserPrompt(from input: ReaderCompanionInput) -> String {
        let abstract = input.abstractText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = input.tagNames.isEmpty ? "None" : input.tagNames.joined(separator: ", ")
        let documentText = input.documentText.isEmpty ? "Unavailable" : input.documentText
        let recentComments = input.recentComments.isEmpty
            ? "None"
            : input.recentComments.map { comment in
                "[Page \(comment.passage.pageNumber)] \(comment.text)"
            }
            .joined(separator: "\n")

        return """
        Decide whether a mischievous but rigorous reader elf should interrupt a researcher with a critique about the current passage.

        Return strict JSON only, with exactly these keys:
        {
          "shouldInterrupt": boolean,
          "mood": "skeptical" | "alarmed" | "amused" | "intrigued",
          "comment": string
        }

        Rules:
        - The elf is lively, skeptical, and academically grounded.
        - Prefer criticism: weak assumptions, missing controls, unclear causal claims, overreach, vague baselines, dataset bias, or evaluation holes.
        - If the passage is routine, unsupported by the provided context, or too similar to recent comments, return {"shouldInterrupt": false, "mood": "skeptical", "comment": ""}.
        - If interrupting, keep the comment to at most 2 sentences and about 220 characters.
        - Do not quote the full passage back.
        - Do not output markdown or any text outside the JSON object.

        Focus passage (page \(input.focusPassage.pageNumber), source: \(input.focusPassage.source.rawValue)):
        \(input.focusPassage.quotedText)

        Paper title: \(input.paperTitle)
        Authors: \(input.authorsText)
        Tags: \(tags)
        Abstract: \(abstract.isEmpty ? "None" : abstract)
        Document context truncated: \(input.documentWasTruncated ? "true" : "false")
        Recent elf comments:
        \(recentComments)

        Full document text:
        \(documentText)
        """
    }

    private var systemPrompt: String {
        """
        You are an autonomous reader companion embedded inside an academic paper reader.
        Your job is to opportunistically critique the paper when the current passage exposes a meaningful weakness or tension.
        Be sharp, specific, and grounded in the supplied passage and paper context.
        """
    }

    private func parseOutput(from content: String) throws -> ReaderCompanionOutput {
        let jsonText = extractJSONObject(from: content) ?? content
        guard let data = jsonText.data(using: .utf8) else {
            throw ReaderCompanionError.invalidResponse
        }

        let payload: ReaderCompanionResponsePayload
        do {
            payload = try decoder.decode(ReaderCompanionResponsePayload.self, from: data)
        } catch {
            throw ReaderCompanionError.invalidResponse
        }
        let trimmedComment = payload.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let mood = ReaderElfMood(rawValue: payload.mood) ?? .skeptical

        if payload.shouldInterrupt {
            guard trimmedComment.isEmpty == false else {
                throw ReaderCompanionError.invalidResponse
            }
        }

        return ReaderCompanionOutput(
            shouldInterrupt: payload.shouldInterrupt,
            mood: mood,
            comment: trimmedComment
        )
    }

    private func extractJSONObject(from content: String) -> String? {
        guard let startIndex = content.firstIndex(of: "{"),
              let endIndex = content.lastIndex(of: "}") else {
            return nil
        }

        return String(content[startIndex...endIndex])
    }
}

private struct ReaderCompanionResponsePayload: Decodable {
    let shouldInterrupt: Bool
    let mood: String
    let comment: String
}
