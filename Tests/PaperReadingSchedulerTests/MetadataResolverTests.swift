import Foundation
import XCTest
@testable import PaperReadingScheduler

final class MetadataResolverTests: XCTestCase {
    func testArxivURLResolvesMetadataAndPDF() async throws {
        let resolver = MetadataResolver(networking: StubNetworking { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Self.arxivResponse.data(using: .utf8)!, response)
        })

        let result = try await resolver.resolve(url: URL(string: "https://arxiv.org/abs/2401.00001")!)

        XCTAssertEqual(result.title, "Planning with Language Models")
        XCTAssertEqual(result.authors, ["Jane Doe", "John Roe"])
        XCTAssertEqual(result.abstractText, "A compact abstract for testing.")
        XCTAssertEqual(result.arxivID, "2401.00001")
        XCTAssertEqual(result.doi, "10.1000/test-doi")
        XCTAssertEqual(result.publishedYear, 2026)
        XCTAssertEqual(result.sourceURL?.absoluteString, "https://arxiv.org/abs/2401.00001")
        XCTAssertEqual(result.pdfURL?.absoluteString, "https://arxiv.org/pdf/2401.00001.pdf")
    }

    func testDirectPDFURLFallsBackToFilename() async throws {
        let resolver = MetadataResolver(networking: StubNetworking { _ in
            XCTFail("Direct PDF imports should not hit the network")
            throw URLError(.badURL)
        })

        let result = try await resolver.resolve(url: URL(string: "https://example.com/papers/awesome-paper.pdf")!)

        XCTAssertEqual(result.title, "awesome paper")
        XCTAssertNil(result.arxivID)
        XCTAssertNil(result.doi)
        XCTAssertNil(result.publishedYear)
        XCTAssertEqual(result.pdfURL?.absoluteString, "https://example.com/papers/awesome-paper.pdf")
        XCTAssertEqual(result.sourceURL?.absoluteString, "https://example.com/papers/awesome-paper.pdf")
    }

    private static let arxivResponse = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <entry>
        <id>http://arxiv.org/abs/2401.00001v1</id>
        <updated>2026-03-01T00:00:00Z</updated>
        <published>2026-03-01T00:00:00Z</published>
        <title>Planning with Language Models</title>
        <summary>A compact abstract for testing.</summary>
        <arxiv:doi xmlns:arxiv="http://arxiv.org/schemas/atom">10.1000/test-doi</arxiv:doi>
        <author><name>Jane Doe</name></author>
        <author><name>John Roe</name></author>
        <link href="https://arxiv.org/abs/2401.00001v1" rel="alternate" type="text/html" />
        <link title="pdf" href="https://arxiv.org/pdf/2401.00001.pdf" rel="related" type="application/pdf" />
      </entry>
    </feed>
    """
}
