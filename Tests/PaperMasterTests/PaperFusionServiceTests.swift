import Foundation
import XCTest
@testable import PaperMaster

final class PaperFusionServiceTests: XCTestCase {
    func testOpenAICompatibleFusionGeneratorNormalizesAndCapsIdeasToThreeCards() async throws {
        let networking = StubHTTPNetworking { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

            let body = """
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\"ideas\\":[{\\"title\\":\\"Agentic Proof Search\\",\\"hypothesis\\":\\"Combine search over theorem branches with tool-using agents.\\",\\"rationale\\":\\"One paper contributes search structure while the other contributes adaptive agent control.\\"},{\\"title\\":\\"Calibrated Memory Routing\\",\\"hypothesis\\":\\"Route long-context evidence using confidence-aware memory slots.\\",\\"rationale\\":\\"The papers align on retrieval, uncertainty, and long-horizon context management.\\"},{\\"title\\":\\"Differentiable Reading Scheduler\\",\\"hypothesis\\":\\"Learn when to read papers based on downstream idea yield.\\",\\"rationale\\":\\"One paper models scheduling, the other contributes differentiable optimization.\\"},{\\"title\\":\\"Extra Idea\\",\\"hypothesis\\":\\"This should be dropped.\\",\\"rationale\\":\\"The UI only accepts three cards.\\"}]}"
                  }
                }
              ]
            }
            """

            return (Data(body.utf8), TestSupport.httpResponse())
        }

        let generator = OpenAICompatiblePaperFusionGenerator(networking: networking)
        let ideas = try await generator.generateIdeas(
            for: [
                PaperFusionInput(
                    paperID: UUID(),
                    title: "Search Paper",
                    authorsText: "A. Author",
                    abstractText: "Search across theorem proving states.",
                    tagNames: ["search", "theorem-proving"]
                ),
                PaperFusionInput(
                    paperID: UUID(),
                    title: "Agent Paper",
                    authorsText: "B. Author",
                    abstractText: "Tool-using agents with memory.",
                    tagNames: ["agents", "memory"]
                )
            ],
            configuration: AIProviderConfiguration(
                baseURL: URL(string: "https://api.openai.com/v1")!,
                model: "gpt-4o-mini",
                apiKey: "sk-test"
            )
        )

        XCTAssertEqual(ideas.count, 3)
        XCTAssertEqual(ideas.map(\.title), [
            "Agentic Proof Search",
            "Calibrated Memory Routing",
            "Differentiable Reading Scheduler"
        ])
    }

    func testOpenAICompatibleFusionGeneratorRejectsIncompleteIdeaPayload() async {
        let networking = StubHTTPNetworking { _ in
            let body = """
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\"ideas\\":[{\\"title\\":\\"Only One\\",\\"hypothesis\\":\\"Too short.\\",\\"rationale\\":\\"Not enough ideas.\\"}]}"
                  }
                }
              ]
            }
            """

            return (Data(body.utf8), TestSupport.httpResponse())
        }

        let generator = OpenAICompatiblePaperFusionGenerator(networking: networking)

        do {
            _ = try await generator.generateIdeas(
                for: [
                    PaperFusionInput(
                        paperID: UUID(),
                        title: "Paper One",
                        authorsText: "A. Author",
                        abstractText: "Abstract one",
                        tagNames: ["one"]
                    ),
                    PaperFusionInput(
                        paperID: UUID(),
                        title: "Paper Two",
                        authorsText: "B. Author",
                        abstractText: "Abstract two",
                        tagNames: ["two"]
                    )
                ],
                configuration: AIProviderConfiguration(
                    baseURL: URL(string: "https://api.openai.com/v1")!,
                    model: "gpt-4o-mini",
                    apiKey: "sk-test"
                )
            )
            XCTFail("Expected invalidResponse error")
        } catch let error as PaperFusionError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAIProviderReadinessIsIndependentFromImportAutoTaggingToggle() {
        let settings = UserSettings(
            aiTaggingEnabled: false,
            aiTaggingBaseURLString: "https://api.openai.com/v1",
            aiTaggingModel: "gpt-4o-mini"
        )

        let providerReadiness = settings.aiProviderReadiness(apiKey: "sk-test")
        let taggingReadiness = settings.aiTaggingReadiness(apiKey: "sk-test")

        guard case let .ready(configuration) = providerReadiness else {
            XCTFail("Expected provider readiness to be ready")
            return
        }

        XCTAssertEqual(configuration.model, "gpt-4o-mini")
        XCTAssertEqual(taggingReadiness, .disabled)
    }
}
