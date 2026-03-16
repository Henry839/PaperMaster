import Foundation
import XCTest
@testable import PaperMaster

final class ReaderCompanionServiceTests: XCTestCase {
    func testReaderCompanionGeneratorParsesStructuredJSONComment() async throws {
        let networking = StubHTTPNetworking { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            let data = Data(#"{"choices":[{"message":{"content":"{\"shouldInterrupt\":true,\"mood\":\"skeptical\",\"comment\":\"This baseline claim reads stronger than the evidence shown.\"}"}}]}"#.utf8)
            return (data, try XCTUnwrap(response))
        }

        let generator = OpenAICompatibleReaderCompanionGenerator(networking: networking)
        let output = try await generator.generateComment(
            for: input(),
            configuration: AIProviderConfiguration(
                baseURL: URL(string: "https://api.openai.com/v1")!,
                model: "gpt-4o-mini",
                apiKey: "sk-test"
            )
        )

        XCTAssertTrue(output.shouldInterrupt)
        XCTAssertEqual(output.mood, .skeptical)
        XCTAssertEqual(output.comment, "This baseline claim reads stronger than the evidence shown.")
    }

    func testReaderCompanionGeneratorAcceptsNoInterruptDecision() async throws {
        let networking = StubHTTPNetworking { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            let data = Data(#"{"choices":[{"message":{"content":"{\"shouldInterrupt\":false,\"mood\":\"skeptical\",\"comment\":\"\"}"}}]}"#.utf8)
            return (data, try XCTUnwrap(response))
        }

        let generator = OpenAICompatibleReaderCompanionGenerator(networking: networking)
        let output = try await generator.generateComment(
            for: input(),
            configuration: AIProviderConfiguration(
                baseURL: URL(string: "https://api.openai.com/v1")!,
                model: "gpt-4o-mini",
                apiKey: "sk-test"
            )
        )

        XCTAssertFalse(output.shouldInterrupt)
        XCTAssertEqual(output.comment, "")
    }

    func testReaderCompanionGeneratorRejectsMalformedJSON() async {
        let networking = StubHTTPNetworking { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            let data = Data(#"{"choices":[{"message":{"content":"not json"}}]}"#.utf8)
            return (data, try XCTUnwrap(response))
        }

        let generator = OpenAICompatibleReaderCompanionGenerator(networking: networking)

        await XCTAssertThrowsErrorAsync(
            try await generator.generateComment(
                for: self.input(),
                configuration: AIProviderConfiguration(
                    baseURL: URL(string: "https://api.openai.com/v1")!,
                    model: "gpt-4o-mini",
                    apiKey: "sk-test"
                )
            )
        ) { error in
            XCTAssertEqual(error as? ReaderCompanionError, .invalidResponse)
        }
    }

    func testReaderCompanionGeneratorSurfacesProviderErrors() async {
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

        let generator = OpenAICompatibleReaderCompanionGenerator(networking: networking)

        await XCTAssertThrowsErrorAsync(
            try await generator.generateComment(
                for: self.input(),
                configuration: AIProviderConfiguration(
                    baseURL: URL(string: "https://api.openai.com/v1")!,
                    model: "gpt-4o-mini",
                    apiKey: "sk-test"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ReaderCompanionError,
                .providerError(statusCode: 503, message: "Provider unavailable")
            )
        }
    }

    private func input() -> ReaderCompanionInput {
        ReaderCompanionInput(
            focusPassage: ReaderFocusPassageSnapshot(
                pageIndex: 1,
                quotedText: "We compare only against two baselines.",
                rects: [ReaderAnnotationRect(rect: CGRect(x: 12, y: 20, width: 90, height: 14))],
                source: .viewport
            )!,
            paperTitle: "Paper",
            authorsText: "Author One",
            abstractText: "Abstract",
            tagNames: ["ml"],
            documentText: "Full paper text",
            documentWasTruncated: false,
            recentComments: []
        )
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
