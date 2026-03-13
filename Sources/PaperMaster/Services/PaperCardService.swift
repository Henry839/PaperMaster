import Foundation

struct PaperCardInput: Sendable {
    let paperTitle: String
    let authorsText: String
    let abstractText: String
    let venueText: String
    let citationText: String
    let tagNames: [String]
    let notesText: String
}

struct PaperCardOutput: Equatable, Sendable {
    let headline: String
    let venueLine: String
    let citationLine: String
    let keywords: [String]
    let sections: [PaperCardSection]
}

enum PaperCardError: LocalizedError, Equatable {
    case generatorUnavailable
    case providerNotConfigured(String)
    case invalidEndpoint
    case invalidResponse
    case providerError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .generatorUnavailable:
            return "Paper Card generation is not available in this build."
        case let .providerNotConfigured(message):
            return message
        case .invalidEndpoint:
            return "The Paper Card endpoint is invalid."
        case .invalidResponse:
            return "Paper Card generation returned an invalid response."
        case let .providerError(statusCode, message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "Paper Card generation failed with status \(statusCode)."
                : "Paper Card generation failed with status \(statusCode): \(trimmed)"
        }
    }
}

protocol PaperCardGenerating: Sendable {
    func generatePaperCard(
        for input: PaperCardInput,
        configuration: AIProviderConfiguration
    ) async throws -> PaperCardOutput
}

struct OpenAICompatiblePaperCardGenerator: PaperCardGenerating {
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

    func generatePaperCard(
        for input: PaperCardInput,
        configuration: AIProviderConfiguration
    ) async throws -> PaperCardOutput {
        guard let endpoint = makeOpenAIChatCompletionsEndpoint(from: configuration.baseURL) else {
            throw PaperCardError.invalidEndpoint
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
            throw PaperCardError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let providerMessage = (try? decoder.decode(OpenAIErrorResponse.self, from: data).error.message) ?? ""
            throw PaperCardError.providerError(statusCode: httpResponse.statusCode, message: providerMessage)
        }

        let payload = try decoder.decode(OpenAIChatCompletionsResponse.self, from: data)
        guard let content = payload.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              content.isEmpty == false else {
            throw PaperCardError.invalidResponse
        }

        guard let responseData = content.data(using: .utf8),
              let decoded = try? decoder.decode(PaperCardResponse.self, from: responseData) else {
            throw PaperCardError.invalidResponse
        }

        let headline = decoded.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard headline.isEmpty == false else {
            throw PaperCardError.invalidResponse
        }

        let sections = decoded.sections.compactMap { section -> PaperCardSection? in
            let id = section.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let emoji = section.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = normalizeParagraph(section.body)
            guard id.isEmpty == false, title.isEmpty == false, body.isEmpty == false else {
                return nil
            }
            return PaperCardSection(id: id, title: title, emoji: emoji.isEmpty ? "•" : emoji, body: body)
        }

        guard sections.count >= 3 else {
            throw PaperCardError.invalidResponse
        }

        let keywords = Array(Set(decoded.keywords.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { $0.isEmpty == false })).sorted()

        return PaperCardOutput(
            headline: headline,
            venueLine: normalizeParagraph(decoded.venueLine),
            citationLine: normalizeParagraph(decoded.citationLine),
            keywords: keywords,
            sections: Array(sections.prefix(6))
        )
    }

    private func normalizeParagraph(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeUserPrompt(from input: PaperCardInput) -> String {
        """
        Create a concise research paper card in Chinese for the following paper.
        Return strict JSON only. Do not wrap it in markdown fences.

        JSON schema:
        {
          "headline": "string",
          "venueLine": "string",
          "citationLine": "string",
          "keywords": ["string"],
          "sections": [
            {
              "id": "summary|innovation|method|dataset|comparison|limitations",
              "title": "string",
              "emoji": "string",
              "body": "string"
            }
          ]
        }

        Requirements:
        - Write in Chinese.
        - Keep the tone factual and compact.
        - Prefer 5 to 6 sections.
        - The sections should mirror a readable paper-card layout.
        - Do not invent venue/citation details that are unavailable. If unknown, say so briefly.
        - Use the provided tags when helpful, but do not repeat them mechanically.

        Title: \(input.paperTitle)
        Authors: \(input.authorsText)
        Venue: \(input.venueText)
        Citation Info: \(input.citationText)
        Tags: \(input.tagNames.joined(separator: ", "))
        Notes: \(input.notesText)
        Abstract: \(input.abstractText)
        """
    }

    private var systemPrompt: String {
        "You create structured research paper cards for local knowledge libraries."
    }
}

private struct PaperCardResponse: Decodable {
    struct Section: Decodable {
        let id: String
        let title: String
        let emoji: String
        let body: String
    }

    let headline: String
    let venueLine: String
    let citationLine: String
    let keywords: [String]
    let sections: [Section]
}

struct PaperCardHTMLRenderer {
    func render(card: PaperCardOutput, paper: Paper) -> String {
        let escapedTitle = escapeHTML(paper.title)
        let escapedAuthors = escapeHTML(paper.authorsDisplayText)
        let escapedHeadline = escapeHTML(card.headline)
        let escapedVenue = escapeHTML(card.venueLine)
        let escapedCitation = escapeHTML(card.citationLine)
        let keywordHTML = card.keywords.map {
            "<span class=\"chip\">\(escapeHTML($0))</span>"
        }.joined(separator: "\n")
        let sectionsHTML = card.sections.map { section in
            """
            <section class="card-section">
              <h3><span class="emoji">\(escapeHTML(section.emoji))</span>\(escapeHTML(section.title))</h3>
              <p>\(escapeHTML(section.body))</p>
            </section>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapedTitle) · Paper Card</title>
          <style>
            :root {
              --bg: #f4f1eb;
              --card: #ffffff;
              --text: #1e2430;
              --muted: #687182;
              --accent: #546ee5;
              --accent-soft: rgba(84, 110, 229, 0.12);
              --border: rgba(30, 36, 48, 0.08);
            }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              background:
                radial-gradient(circle at top left, rgba(84, 110, 229, 0.12), transparent 28%),
                linear-gradient(180deg, #fbfaf7 0%, var(--bg) 100%);
              color: var(--text);
            }
            .page {
              width: min(900px, calc(100vw - 32px));
              margin: 32px auto 48px;
              padding: 28px;
              background: rgba(255,255,255,0.72);
              border: 1px solid var(--border);
              border-radius: 28px;
              backdrop-filter: blur(18px);
              box-shadow: 0 18px 50px rgba(30, 36, 48, 0.08);
            }
            h1 {
              margin: 0 0 10px;
              font-size: clamp(28px, 3.8vw, 42px);
              line-height: 1.08;
            }
            .meta, .submeta {
              color: var(--muted);
              font-size: 15px;
              line-height: 1.6;
            }
            .headline {
              margin: 20px 0 14px;
              padding: 16px 18px;
              border-radius: 18px;
              background: linear-gradient(135deg, var(--accent-soft), rgba(255,255,255,0.95));
              border: 1px solid rgba(84, 110, 229, 0.18);
              font-weight: 600;
              line-height: 1.6;
            }
            .chips {
              display: flex;
              flex-wrap: wrap;
              gap: 8px;
              margin: 18px 0 24px;
            }
            .chip {
              padding: 7px 12px;
              border-radius: 999px;
              background: rgba(132, 92, 217, 0.10);
              color: #7a4fd1;
              font-size: 13px;
              font-weight: 600;
            }
            .sections {
              display: grid;
              gap: 14px;
            }
            .card-section {
              padding: 18px 18px 16px;
              background: var(--card);
              border-radius: 20px;
              border: 1px solid var(--border);
              box-shadow: 0 8px 20px rgba(30, 36, 48, 0.04);
            }
            .card-section h3 {
              margin: 0 0 10px;
              font-size: 16px;
            }
            .emoji {
              margin-right: 8px;
            }
            .card-section p {
              margin: 0;
              line-height: 1.75;
              color: #2d3542;
              white-space: pre-wrap;
            }
          </style>
        </head>
        <body>
          <main class="page">
            <h1>\(escapedTitle)</h1>
            <div class="meta">\(escapedVenue)</div>
            <div class="submeta">作者: \(escapedAuthors)</div>
            <div class="submeta">\(escapedCitation)</div>
            <div class="headline">\(escapedHeadline)</div>
            <div class="chips">\(keywordHTML)</div>
            <div class="sections">\(sectionsHTML)</div>
          </main>
        </body>
        </html>
        """
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
