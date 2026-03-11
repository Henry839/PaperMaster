import Foundation
import XCTest
@testable import PaperMaster

final class PaperTaggingServiceTests: XCTestCase {
    func testOpenAICompatibleTaggerNormalizesDeduplicatesAndCapsTags() async throws {
        let networking = StubHTTPNetworking { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

            let body = """
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\"tags\\":[\\"Agents\\",\\"planning\\",\\"agents\\",\\"llms\\",\\"memory\\",\\"retrieval\\"]}"
                  }
                }
              ]
            }
            """

            return (Data(body.utf8), TestSupport.httpResponse())
        }

        let tagger = OpenAICompatiblePaperTagger(networking: networking)
        let tags = try await tagger.generateTags(
            for: PaperTaggingInput(
                title: "Memory-Augmented Agents",
                abstractText: "A paper about planning and retrieval for LLM agents.",
                existingTags: ["agents", "memory"]
            ),
            configuration: PaperTaggingConfiguration(
                baseURL: URL(string: "https://api.openai.com/v1")!,
                model: "gpt-4o-mini",
                apiKey: "sk-test"
            )
        )

        XCTAssertEqual(tags, ["agents", "planning", "llms", "memory", "retrieval"])
    }

    func testTagChipPaletteIsStableAndDistinct() {
        let agentsA = TagChipStyle.palette(for: "agents")
        let agentsB = TagChipStyle.palette(for: "agents")
        let planning = TagChipStyle.palette(for: "planning")

        XCTAssertEqual(agentsA, agentsB)
        XCTAssertNotEqual(agentsA, planning)
    }
}
