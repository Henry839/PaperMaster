import XCTest
@testable import PaperMaster

final class HotPaperDiscoveryServiceTests: XCTestCase {
    func testDiscoverPapersParsesAndSortsByFreshnessAndLibrarySignals() async throws {
        let feedData = Self.sampleFeed.data(using: .utf8)!
        let networking = StubHTTPNetworking { request in
            XCTAssertEqual(request.url?.host, "export.arxiv.org")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (feedData, response)
        }

        let service = ArXivHotPaperDiscoveryService(
            networking: networking,
            now: { ISO8601DateFormatter().date(from: "2026-03-19T12:00:00Z")! }
        )

        let papers = try await service.discoverPapers(
            in: .artificialIntelligence,
            librarySignals: ["ICLR", "agents", "planning"]
        )

        XCTAssertEqual(papers.count, 2)
        XCTAssertEqual(papers.first?.title, "Planning Agents in Open Worlds")
        XCTAssertEqual(papers.first?.scoreLabel, "Very hot")
        XCTAssertTrue(papers.first?.reasons.contains("2x library match") == true)
        XCTAssertEqual(papers.last?.title, "Benchmarking Symbolic Search")
    }

    func testDiscoverPapersThrowsForBadStatusCode() async {
        let networking = StubHTTPNetworking { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }

        let service = ArXivHotPaperDiscoveryService(networking: networking)

        await XCTAssertThrowsErrorAsync(
            try await service.discoverPapers(in: .machineLearning, librarySignals: [])
        )
    }

    private static let sampleFeed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <entry>
        <id>https://arxiv.org/abs/2603.00001v1</id>
        <updated>2026-03-18T09:00:00Z</updated>
        <published>2026-03-18T09:00:00Z</published>
        <title>Planning Agents in Open Worlds</title>
        <summary>Agents use planning and memory to solve open-world tasks.</summary>
        <author><name>Alice Example</name></author>
        <author><name>Bob Example</name></author>
        <link href="https://arxiv.org/abs/2603.00001v1" rel="alternate" type="text/html" />
        <link title="pdf" href="https://arxiv.org/pdf/2603.00001v1.pdf" rel="related" type="application/pdf" />
        <category term="cs.AI" />
      </entry>
      <entry>
        <id>https://arxiv.org/abs/2603.00002v1</id>
        <updated>2026-03-12T09:00:00Z</updated>
        <published>2026-03-12T09:00:00Z</published>
        <title>Benchmarking Symbolic Search</title>
        <summary>A benchmark suite for symbolic search and theorem proving.</summary>
        <author><name>Carol Example</name></author>
        <link href="https://arxiv.org/abs/2603.00002v1" rel="alternate" type="text/html" />
        <category term="cs.AI" />
      </entry>
    </feed>
    """
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw an error", file: file, line: line)
    } catch {
    }
}
