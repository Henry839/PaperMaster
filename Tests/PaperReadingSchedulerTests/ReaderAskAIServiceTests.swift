import Foundation
import XCTest
@testable import PaperReadingScheduler

final class ReaderAskAIServiceTests: XCTestCase {
    func testOpenAICompatibleReaderAnswererReturnsTrimmedAnswerText() async throws {
        let networking = StubHTTPNetworking { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            let data = Data(#"{"choices":[{"message":{"content":"  This passage motivates the core experiment.  "}}]}"#.utf8)
            return (data, try XCTUnwrap(response))
        }

        let answerer = OpenAICompatibleReaderAnswerer(networking: networking)
        let answer = try await answerer.answerQuestion(
            for: ReaderAskAIInput(
                question: "Why is this important?",
                quotedText: "A key result.",
                pageNumber: 3,
                paperTitle: "Paper",
                authorsText: "Author One",
                abstractText: "Abstract",
                tagNames: ["ml"],
                documentText: "Full paper text",
                documentWasTruncated: false
            ),
            configuration: AIProviderConfiguration(
                baseURL: URL(string: "https://api.openai.com/v1")!,
                model: "gpt-4o-mini",
                apiKey: "sk-test"
            )
        )

        XCTAssertEqual(answer, "This passage motivates the core experiment.")
    }

    func testOpenAICompatibleReaderAnswererRejectsEmptyContent() async {
        let networking = StubHTTPNetworking { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            let data = Data(#"{"choices":[{"message":{"content":"   "}}]}"#.utf8)
            return (data, try XCTUnwrap(response))
        }

        let answerer = OpenAICompatibleReaderAnswerer(networking: networking)

        await XCTAssertThrowsErrorAsync(
            try await answerer.answerQuestion(
                for: ReaderAskAIInput(
                    question: "Why is this important?",
                    quotedText: "A key result.",
                    pageNumber: 3,
                    paperTitle: "Paper",
                    authorsText: "Author One",
                    abstractText: "Abstract",
                    tagNames: ["ml"],
                    documentText: "Full paper text",
                    documentWasTruncated: false
                ),
                configuration: AIProviderConfiguration(
                    baseURL: URL(string: "https://api.openai.com/v1")!,
                    model: "gpt-4o-mini",
                    apiKey: "sk-test"
                )
            )
        ) { error in
            XCTAssertEqual(error as? ReaderAnswerError, .invalidResponse)
        }
    }

    func testOpenAICompatibleReaderAnswererSurfacesProviderErrors() async {
        let networking = StubHTTPNetworking { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )
            let data = Data(#"{"error":{"message":"Provider unavailable"}}"#.utf8)
            return (data, try XCTUnwrap(response))
        }

        let answerer = OpenAICompatibleReaderAnswerer(networking: networking)

        await XCTAssertThrowsErrorAsync(
            try await answerer.answerQuestion(
                for: ReaderAskAIInput(
                    question: "Why is this important?",
                    quotedText: "A key result.",
                    pageNumber: 3,
                    paperTitle: "Paper",
                    authorsText: "Author One",
                    abstractText: "Abstract",
                    tagNames: ["ml"],
                    documentText: "Full paper text",
                    documentWasTruncated: false
                ),
                configuration: AIProviderConfiguration(
                    baseURL: URL(string: "https://api.openai.com/v1")!,
                    model: "gpt-4o-mini",
                    apiKey: "sk-test"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ReaderAnswerError,
                .providerError(statusCode: 503, message: "Provider unavailable")
            )
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure @escaping () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw an error", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
