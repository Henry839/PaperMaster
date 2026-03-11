import Foundation

struct PaperTaggingInput: Sendable {
    let title: String
    let abstractText: String
    let existingTags: [String]
}

enum AITaggingReadiness: Equatable {
    case disabled
    case missingBaseURL
    case invalidBaseURL
    case missingModel
    case missingAPIKey
    case ready(PaperTaggingConfiguration)

    var settingsMessage: String {
        switch self {
        case .disabled:
            "AI auto-tagging is off."
        case .missingBaseURL:
            "Enter a base URL to enable AI auto-tagging."
        case .invalidBaseURL:
            "Enter a valid HTTP base URL for the AI provider."
        case .missingModel:
            "Enter a model name for AI auto-tagging."
        case .missingAPIKey:
            "Save an API key in Keychain to enable AI auto-tagging."
        case .ready:
            "AI auto-tagging is ready for new imports."
        }
    }

    var importNotice: String? {
        switch self {
        case .disabled, .ready:
            nil
        case .missingBaseURL, .invalidBaseURL, .missingModel, .missingAPIKey:
            "AI auto-tagging is enabled but not fully configured. Imported without generated tags."
        }
    }
}

protocol PaperTagGenerating: Sendable {
    func generateTags(
        for input: PaperTaggingInput,
        configuration: PaperTaggingConfiguration
    ) async throws -> [String]
}

protocol HTTPNetworking: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionHTTPNetworking: HTTPNetworking {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

enum PaperTaggingError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case providerError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The AI tagger endpoint is invalid."
        case .invalidResponse:
            return "The AI tagger returned an invalid response."
        case let .providerError(statusCode, message):
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedMessage.isEmpty
                ? "The AI tagger failed with status \(statusCode)."
                : "The AI tagger failed with status \(statusCode): \(trimmedMessage)"
        }
    }
}

struct OpenAICompatiblePaperTagger: PaperTagGenerating {
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

    func generateTags(
        for input: PaperTaggingInput,
        configuration: PaperTaggingConfiguration
    ) async throws -> [String] {
        guard let endpoint = makeOpenAIChatCompletionsEndpoint(from: configuration.baseURL) else {
            throw PaperTaggingError.invalidEndpoint
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
            throw PaperTaggingError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let providerMessage = (try? decoder.decode(OpenAIErrorResponse.self, from: data).error.message) ?? ""
            throw PaperTaggingError.providerError(statusCode: httpResponse.statusCode, message: providerMessage)
        }

        let payload = try decoder.decode(OpenAIChatCompletionsResponse.self, from: data)
        guard let content = payload.choices.first?.message.content else {
            throw PaperTaggingError.invalidResponse
        }

        return try decodeTags(from: content)
    }

    private func decodeTags(from content: String) throws -> [String] {
        let candidate = extractJSONObject(from: content)
        guard let jsonData = candidate.data(using: .utf8) else {
            throw PaperTaggingError.invalidResponse
        }

        let result = try decoder.decode(TaggingPayload.self, from: jsonData)
        var normalizedTags: [String] = []
        var seen = Set<String>()

        for tag in result.tags {
            let normalized = Tag.normalize(tag)
            guard normalized.isEmpty == false else { continue }
            guard seen.insert(normalized).inserted else { continue }
            normalizedTags.append(normalized)
            if normalizedTags.count == 5 {
                break
            }
        }

        return normalizedTags
    }

    private func extractJSONObject(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }

        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}") {
            return String(trimmed[firstBrace...lastBrace])
        }

        return trimmed
    }

    private func makeUserPrompt(from input: PaperTaggingInput) -> String {
        let abstract = input.abstractText.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingTagList = input.existingTags.isEmpty ? "None" : input.existingTags.joined(separator: ", ")

        return """
        Suggest up to 5 short topic tags for this paper.
        Reuse the existing library tags when they already fit semantically.
        Return JSON only with this shape: {"tags":["tag-one","tag-two"]}.
        Use lowercase tags, avoid punctuation except hyphens, and avoid generic tags like paper or research.

        Title: \(input.title)
        Abstract: \(abstract.isEmpty ? "None" : abstract)
        Existing library tags: \(existingTagList)
        """
    }

    private var systemPrompt: String {
        "You generate concise topic tags for academic papers."
    }
}

private struct TaggingPayload: Decodable {
    let tags: [String]
}
