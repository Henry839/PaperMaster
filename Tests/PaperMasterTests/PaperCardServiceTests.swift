import Foundation
import XCTest
@testable import PaperMaster

final class PaperCardServiceTests: XCTestCase {
    func testOpenAICompatiblePaperCardGeneratorParsesStructuredResponse() async throws {
        let networking = StubHTTPNetworking { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")

            let body = """
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\"headline\\":\\"提出一种单次训练估计数据贡献的方法\\",\\"venueLine\\":\\"ICLR 2025 · oral\\",\\"citationLine\\":\\"作者：A, B · 引用：2434\\",\\"keywords\\":[\\"Optimization\\",\\"Transformer\\"],\\"sections\\":[{\\"id\\":\\"summary\\",\\"title\\":\\"论文内容\\",\\"emoji\\":\\"📌\\",\\"body\\":\\"提出 In-Run Data Shapley。\\"},{\\"id\\":\\"innovation\\",\\"title\\":\\"创新点\\",\\"emoji\\":\\"💡\\",\\"body\\":\\"用 Taylor 展开近似。\\"},{\\"id\\":\\"method\\",\\"title\\":\\"技术方法\\",\\"emoji\\":\\"🛠️\\",\\"body\\":\\"结合梯度下降和 ghost Hessian。\\"},{\\"id\\":\\"limitations\\",\\"title\\":\\"局限性\\",\\"emoji\\":\\"⚠️\\",\\"body\\":\\"仍需要额外梯度计算。\\"}]}"
                  }
                }
              ]
            }
            """

            return (Data(body.utf8), TestSupport.httpResponse())
        }

        let generator = OpenAICompatiblePaperCardGenerator(networking: networking)
        let output = try await generator.generatePaperCard(
            for: PaperCardInput(
                paperTitle: "Data Shapley in One Training Run",
                authorsText: "A, B",
                abstractText: "Abstract",
                venueText: "ICLR 2025",
                citationText: "2434 citations",
                tagNames: ["optimization"],
                notesText: ""
            ),
            configuration: AIProviderConfiguration(
                baseURL: URL(string: "https://api.openai.com/v1")!,
                model: "gpt-4o-mini",
                apiKey: "sk-test"
            )
        )

        XCTAssertEqual(output.headline, "提出一种单次训练估计数据贡献的方法")
        XCTAssertEqual(output.venueLine, "ICLR 2025 · oral")
        XCTAssertEqual(output.keywords, ["Optimization", "Transformer"])
        XCTAssertEqual(output.sections.count, 4)
        XCTAssertEqual(output.sections.first?.title, "论文内容")
    }
}
