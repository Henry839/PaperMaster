import Foundation

protocol PaperFusionGenerating: Sendable {
    func generateIdeas(
        for inputs: [PaperFusionInput],
        configuration: AIProviderConfiguration
    ) async throws -> [PaperFusionIdea]
}

enum PaperFusionError: LocalizedError, Equatable {
    case notEnoughPapers
    case tooManyPapers(limit: Int)
    case generatorUnavailable
    case providerNotConfigured(String)
    case invalidEndpoint
    case invalidResponse
    case providerError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notEnoughPapers:
            return "Add at least two papers to the reactor before refining."
        case let .tooManyPapers(limit):
            return "The reactor can only handle \(limit) papers at once."
        case .generatorUnavailable:
            return "Paper Fusion Reactor is not available in this build."
        case let .providerNotConfigured(message):
            return message
        case .invalidEndpoint:
            return "The Paper Fusion Reactor endpoint is invalid."
        case .invalidResponse:
            return "The Paper Fusion Reactor returned an invalid response."
        case let .providerError(statusCode, message):
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedMessage.isEmpty
                ? "The Paper Fusion Reactor failed with status \(statusCode)."
                : "The Paper Fusion Reactor failed with status \(statusCode): \(trimmedMessage)"
        }
    }
}

struct OpenAICompatiblePaperFusionGenerator: PaperFusionGenerating {
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

    func generateIdeas(
        for inputs: [PaperFusionInput],
        configuration: AIProviderConfiguration
    ) async throws -> [PaperFusionIdea] {
        guard let endpoint = makeOpenAIChatCompletionsEndpoint(from: configuration.baseURL) else {
            throw PaperFusionError.invalidEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(
            OpenAIChatCompletionsRequest(
                model: configuration.model,
                temperature: 0.7,
                messages: [
                    .init(role: "system", content: systemPrompt),
                    .init(role: "user", content: makeUserPrompt(from: inputs))
                ]
            )
        )

        let (data, response) = try await networking.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PaperFusionError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let providerMessage = (try? decoder.decode(OpenAIErrorResponse.self, from: data).error.message) ?? ""
            throw PaperFusionError.providerError(statusCode: httpResponse.statusCode, message: providerMessage)
        }

        let payload = try decoder.decode(OpenAIChatCompletionsResponse.self, from: data)
        guard let content = payload.choices.first?.message.content else {
            throw PaperFusionError.invalidResponse
        }

        return try decodeIdeas(from: content)
    }

    private func decodeIdeas(from content: String) throws -> [PaperFusionIdea] {
        let candidate = extractJSONObject(from: content)
        guard let jsonData = candidate.data(using: .utf8) else {
            throw PaperFusionError.invalidResponse
        }

        let payload = try decoder.decode(FusionPayload.self, from: jsonData)
        var normalizedIdeas: [PaperFusionIdea] = []
        var seen = Set<String>()

        for idea in payload.ideas {
            let normalizedTitle = idea.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedHypothesis = idea.hypothesis.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedRationale = idea.rationale.trimmingCharacters(in: .whitespacesAndNewlines)

            guard normalizedTitle.isEmpty == false,
                  normalizedHypothesis.isEmpty == false,
                  normalizedRationale.isEmpty == false else {
                continue
            }

            let fingerprint = "\(normalizedTitle.lowercased())|\(normalizedHypothesis.lowercased())"
            guard seen.insert(fingerprint).inserted else { continue }

            normalizedIdeas.append(
                PaperFusionIdea(
                    title: normalizedTitle,
                    hypothesis: normalizedHypothesis,
                    rationale: normalizedRationale
                )
            )

            if normalizedIdeas.count == 3 {
                break
            }
        }

        guard normalizedIdeas.count == 3 else {
            throw PaperFusionError.invalidResponse
        }

        return normalizedIdeas
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

    private func makeUserPrompt(from inputs: [PaperFusionInput]) -> String {
        let materials = inputs.enumerated().map { index, input in
            let abstract = input.abstractText.trimmingCharacters(in: .whitespacesAndNewlines)
            let tags = input.tagNames.isEmpty ? "None" : input.tagNames.joined(separator: ", ")

            return """
            Paper \(index + 1):
            Title: \(input.title)
            Authors: \(input.authorsText.isEmpty ? "Unknown authors" : input.authorsText)
            Tags: \(tags)
            Abstract: \(abstract.isEmpty ? "None" : abstract)
            """
        }
        .joined(separator: "\n\n")

        return """
        Fuse these papers into exactly 3 new research directions.
        Each idea should be plausible, specific, and reflect genuine overlap across the supplied papers.
        Return JSON only with this shape:
        {"ideas":[{"title":"...","hypothesis":"...","rationale":"..."}]}

        \(materials)
        """
    }

    private var systemPrompt: String {
        """
        You are a research strategist combining academic papers into novel but realistic project ideas.
        Produce concise, high-signal proposals without hype, and always return valid JSON.
        """
    }
}

private struct FusionPayload: Decodable {
    let ideas: [FusionIdeaPayload]
}

private struct FusionIdeaPayload: Decodable {
    let title: String
    let hypothesis: String
    let rationale: String
}
