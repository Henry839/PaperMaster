import Foundation
import SwiftData
import XCTest
@testable import PaperReadingScheduler

@MainActor
final class PaperImportServiceTests: XCTestCase {
    func testManualImportDoesNotRequireNetworkMetadata() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(defaultImportBehavior: .scheduleImmediately)
        context.insert(settings)

        let service = PaperImportService(
            metadataResolver: StubMetadataResolver(
                metadata: ResolvedPaperMetadata(title: "", authors: [], abstractText: "", sourceURL: nil, pdfURL: nil)
            )
        )

        let paper = try await service.createPaper(
            from: PaperCaptureRequest(
                manualTitle: "Attention Is All You Need",
                manualAuthors: "Ashish Vaswani, Noam Shazeer",
                tagNames: ["transformers", "nlp"]
            ),
            settings: settings,
            in: context
        )

        XCTAssertEqual(paper.title, "Attention Is All You Need")
        XCTAssertEqual(paper.authors, ["Ashish Vaswani", "Noam Shazeer"])
        XCTAssertEqual(Set(paper.tagNames), Set(["transformers", "nlp"]))
        XCTAssertEqual(paper.status, .scheduled)
        XCTAssertNil(paper.sourceURL)
    }

    func testPDFImportCreatesPartialPaperWithoutMetadataFetch() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(defaultImportBehavior: .scheduleImmediately)
        context.insert(settings)

        let service = PaperImportService(
            metadataResolver: StubMetadataResolver(
                metadata: ResolvedPaperMetadata(title: "", authors: [], abstractText: "", sourceURL: nil, pdfURL: nil)
            )
        )

        let paper = try await service.createPaper(
            from: PaperCaptureRequest(sourceText: "https://example.com/readings/agentic-workflows.pdf"),
            settings: settings,
            in: context
        )

        XCTAssertEqual(paper.title, "agentic workflows")
        XCTAssertEqual(paper.pdfURL?.absoluteString, "https://example.com/readings/agentic-workflows.pdf")
        XCTAssertEqual(paper.sourceURL?.absoluteString, "https://example.com/readings/agentic-workflows.pdf")
        XCTAssertEqual(paper.status, .scheduled)
    }
}
