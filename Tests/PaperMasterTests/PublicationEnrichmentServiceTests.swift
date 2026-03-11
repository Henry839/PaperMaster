import Foundation
import XCTest
@testable import PaperMaster

final class PublicationEnrichmentServiceTests: XCTestCase {
    func testDOIPublishedMatchGeneratesMacroBackedBibTeX() async throws {
        let service = CrossrefPublicationEnricher(
            networking: StubHTTPNetworking { request in
                let url = try XCTUnwrap(request.url)
                XCTAssertEqual(url.absoluteString, "https://api.crossref.org/works/10.1000/test-doi")
                return (
                    Self.crossrefSingleWorkResponse.data(using: .utf8)!,
                    TestSupport.httpResponse(url: url)
                )
            }
        )

        let result = await service.enrich(
            for: PublicationEnrichmentRequest(
                title: "Planning with Language Models",
                authors: ["Jane Doe", "John Roe"],
                sourceURL: URL(string: "https://arxiv.org/abs/2401.00001"),
                pdfURL: URL(string: "https://arxiv.org/pdf/2401.00001.pdf"),
                arxivID: "2401.00001",
                doi: "10.1000/test-doi",
                publishedYear: 2026
            )
        )

        XCTAssertEqual(result.venueKey, "CVPR")
        XCTAssertEqual(result.venueName, "Conference on Computer Vision and Pattern Recognition (CVPR)")
        XCTAssertEqual(result.doi, "10.1000/test-doi")
        XCTAssertEqual(result.bibtex?.contains("@inproceedings"), true)
        XCTAssertEqual(result.bibtex?.contains("booktitle = CVPR"), true)
    }

    func testTitleSearchFallbackFindsPublishedVenueWithoutDOI() async throws {
        let service = CrossrefPublicationEnricher(
            networking: StubHTTPNetworking { request in
                let url = try XCTUnwrap(request.url)
                XCTAssertEqual(url.host, "api.crossref.org")
                XCTAssertEqual(url.path, "/works")
                let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
                XCTAssertEqual(
                    queryItems?.first(where: { $0.name == "query.title" })?.value,
                    "Chain of Thought for Planning"
                )
                return (
                    Self.crossrefSearchResponse.data(using: .utf8)!,
                    TestSupport.httpResponse(url: url)
                )
            }
        )

        let result = await service.enrich(
            for: PublicationEnrichmentRequest(
                title: "Chain of Thought for Planning",
                authors: ["Alex Kim", "Robin Lee"],
                sourceURL: URL(string: "https://arxiv.org/abs/2501.00001"),
                pdfURL: nil,
                arxivID: "2501.00001",
                doi: nil,
                publishedYear: 2025
            )
        )

        XCTAssertEqual(result.venueKey, "NIPS")
        XCTAssertEqual(result.venueName, "Advances in Neural Information Processing Systems (NeurIPS)")
        XCTAssertEqual(result.bibtex?.contains("booktitle = NIPS"), true)
    }

    func testUnverifiedArxivFallsBackToExportBibTeXCitation() async throws {
        let service = CrossrefPublicationEnricher(
            networking: StubHTTPNetworking { request in
                let url = try XCTUnwrap(request.url)

                switch url.host {
                case "api.crossref.org":
                    return (
                        Self.emptyCrossrefSearchResponse.data(using: .utf8)!,
                        TestSupport.httpResponse(url: url)
                    )
                case "arxiv.org":
                    if url.path == "/abs/2603.05565" {
                        return (
                            Self.arxivAbstractPageResponse.data(using: .utf8)!,
                            TestSupport.httpResponse(url: url)
                        )
                    }
                    if url.path == "/bibtex/2603.05565" {
                        return (
                            Self.arxivBibTeXResponse.data(using: .utf8)!,
                            TestSupport.httpResponse(url: url)
                        )
                    }
                    XCTFail("Unexpected arXiv URL: \(url.absoluteString)")
                    throw URLError(.badURL)
                default:
                    XCTFail("Unexpected host: \(url.absoluteString)")
                    throw URLError(.badURL)
                }
            }
        )

        let result = await service.enrich(
            for: PublicationEnrichmentRequest(
                title: "When AI Levels the Playing Field",
                authors: ["Xupeng Chen", "Shuchen Meng"],
                sourceURL: URL(string: "https://arxiv.org/abs/2603.05565"),
                pdfURL: URL(string: "https://arxiv.org/pdf/2603.05565.pdf"),
                arxivID: "2603.05565",
                doi: nil,
                publishedYear: 2026
            )
        )

        XCTAssertNil(result.venueKey)
        XCTAssertNil(result.venueName)
        XCTAssertEqual(result.bibtex?.contains("@misc{chen2026playingfield"), true)
    }

    private static let crossrefSingleWorkResponse = """
    {
      "message": {
        "DOI": "10.1000/test-doi",
        "title": ["Planning with Language Models"],
        "container-title": ["2026 IEEE/CVF Conference on Computer Vision and Pattern Recognition (CVPR)"],
        "short-container-title": ["CVPR"],
        "author": [
          {"given": "Jane", "family": "Doe"},
          {"given": "John", "family": "Roe"}
        ],
        "type": "proceedings-article",
        "issued": {"date-parts": [[2026]]},
        "page": "1-10",
        "event": {"name": "Conference on Computer Vision and Pattern Recognition"}
      }
    }
    """

    private static let crossrefSearchResponse = """
    {
      "message": {
        "items": [
          {
            "DOI": "10.1000/neurips-test",
            "title": ["Chain of Thought for Planning"],
            "container-title": ["Advances in Neural Information Processing Systems"],
            "short-container-title": ["NeurIPS"],
            "author": [
              {"given": "Alex", "family": "Kim"},
              {"given": "Robin", "family": "Lee"}
            ],
            "type": "proceedings-article",
            "issued": {"date-parts": [[2025]]}
          }
        ]
      }
    }
    """

    private static let emptyCrossrefSearchResponse = """
    {
      "message": {
        "items": []
      }
    }
    """

    private static let arxivAbstractPageResponse = #"""
    <html>
      <body>
        <a href="/bibtex/2603.05565">Export BibTeX Citation</a>
      </body>
    </html>
    """#

    private static let arxivBibTeXResponse = #"""
    <html>
      <body>
        <pre>
        @misc{chen2026playingfield,
          title = {When AI Levels the Playing Field},
          author = {Xupeng Chen and Shuchen Meng},
          year = {2026}
        }
        </pre>
      </body>
    </html>
    """#
}
