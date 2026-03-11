import Foundation

struct AIProviderConfiguration: Equatable, Sendable {
    let baseURL: URL
    let model: String
    let apiKey: String
}

typealias PaperTaggingConfiguration = AIProviderConfiguration

enum AIProviderReadiness: Equatable {
    case missingBaseURL
    case invalidBaseURL
    case missingModel
    case missingAPIKey
    case ready(AIProviderConfiguration)

    var settingsMessage: String {
        switch self {
        case .missingBaseURL:
            "Enter a base URL to enable AI features."
        case .invalidBaseURL:
            "Enter a valid HTTP base URL for the AI provider."
        case .missingModel:
            "Enter a model name for AI features."
        case .missingAPIKey:
            "Save an API key in Keychain to enable AI features."
        case .ready:
            "AI provider is ready for Fusion Reactor and optional import auto-tagging."
        }
    }

    var configuration: AIProviderConfiguration? {
        guard case let .ready(configuration) = self else { return nil }
        return configuration
    }
}

func makeOpenAIChatCompletionsEndpoint(from baseURL: URL) -> URL? {
    let trimmedPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if trimmedPath.hasSuffix("chat/completions") {
        return baseURL
    }
    return baseURL.appendingPathComponent("chat").appendingPathComponent("completions")
}

struct OpenAIChatCompletionsRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let temperature: Double
    let messages: [Message]
}

struct OpenAIChatCompletionsResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

struct OpenAIErrorResponse: Decodable {
    struct ErrorPayload: Decodable {
        let message: String
    }

    let error: ErrorPayload
}
