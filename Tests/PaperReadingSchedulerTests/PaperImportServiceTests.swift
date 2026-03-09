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

        let result = try await service.createPaper(
            from: PaperCaptureRequest(
                manualTitle: "Attention Is All You Need",
                manualAuthors: "Ashish Vaswani, Noam Shazeer",
                tagNames: ["transformers", "nlp"]
            ),
            settings: settings,
            in: context
        )
        let paper = result.paper

        XCTAssertEqual(paper.title, "Attention Is All You Need")
        XCTAssertEqual(paper.authors, ["Ashish Vaswani", "Noam Shazeer"])
        XCTAssertEqual(Set(paper.tagNames), Set(["transformers", "nlp"]))
        XCTAssertEqual(paper.status, .scheduled)
        XCTAssertNil(paper.sourceURL)
        XCTAssertNil(result.notice)
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

        let result = try await service.createPaper(
            from: PaperCaptureRequest(sourceText: "https://example.com/readings/agentic-workflows.pdf"),
            settings: settings,
            in: context
        )
        let paper = result.paper

        XCTAssertEqual(paper.title, "agentic workflows")
        XCTAssertEqual(paper.pdfURL?.absoluteString, "https://example.com/readings/agentic-workflows.pdf")
        XCTAssertEqual(paper.sourceURL?.absoluteString, "https://example.com/readings/agentic-workflows.pdf")
        XCTAssertEqual(paper.status, .scheduled)
        XCTAssertNil(result.notice)
    }

    func testAutoTaggingReusesExistingTagsAndPersistsNewOnes() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(defaultImportBehavior: .scheduleImmediately, aiTaggingEnabled: true)
        context.insert(settings)
        context.insert(Tag(name: "agents"))
        let credentialStore = FakeTaggingCredentialStore(apiKey: "sk-test")
        let expectedModel = settings.aiTaggingModel
        let tagger = SpyPaperTagger { input, configuration in
            XCTAssertEqual(input.title, "Toolformer")
            XCTAssertTrue(input.existingTags.contains("agents"))
            XCTAssertEqual(configuration.model, expectedModel)
            return ["agents", "LLMs", "planning", "agents"]
        }
        let service = PaperImportService(
            metadataResolver: StubMetadataResolver(
                metadata: ResolvedPaperMetadata(
                    title: "Toolformer",
                    authors: [],
                    abstractText: "An abstract about tool-using language models.",
                    sourceURL: URL(string: "https://example.com/toolformer"),
                    pdfURL: nil
                )
            ),
            tagGenerator: tagger,
            credentialStore: credentialStore
        )

        let result = try await service.createPaper(
            from: PaperCaptureRequest(sourceText: "https://example.com/toolformer"),
            settings: settings,
            in: context
        )

        XCTAssertNil(result.notice)
        XCTAssertEqual(Set(result.paper.tagNames), Set(["agents", "llms", "planning"]))
        XCTAssertEqual(tagger.callCount, 1)

        let storedTags = try context.fetch(FetchDescriptor<Tag>())
        XCTAssertEqual(Set(storedTags.map(\.name)), Set(["agents", "llms", "planning"]))
    }

    func testAutoTaggingFailureDoesNotBlockImport() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(defaultImportBehavior: .scheduleImmediately, aiTaggingEnabled: true)
        context.insert(settings)
        let service = PaperImportService(
            metadataResolver: StubMetadataResolver(
                metadata: ResolvedPaperMetadata(
                    title: "Failure Recovery",
                    authors: [],
                    abstractText: "Still should import.",
                    sourceURL: nil,
                    pdfURL: nil
                )
            ),
            tagGenerator: SpyPaperTagger { _, _ in
                throw TestError(message: "Provider unavailable")
            },
            credentialStore: FakeTaggingCredentialStore(apiKey: "sk-test")
        )

        let result = try await service.createPaper(
            from: PaperCaptureRequest(sourceText: "https://example.com/failure-recovery"),
            settings: settings,
            in: context
        )

        XCTAssertEqual(result.paper.title, "Failure Recovery")
        XCTAssertTrue(result.paper.tagNames.isEmpty)
        XCTAssertEqual(result.notice, "AI auto-tagging failed. Imported without generated tags.")
    }

    func testAutoTaggingSkipsWhenDisabled() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(defaultImportBehavior: .scheduleImmediately, aiTaggingEnabled: false)
        context.insert(settings)
        let tagger = SpyPaperTagger { _, _ in
            XCTFail("Auto tagger should not run when disabled")
            return []
        }
        let service = PaperImportService(
            metadataResolver: StubMetadataResolver(
                metadata: ResolvedPaperMetadata(
                    title: "Disabled",
                    authors: [],
                    abstractText: "Disabled tagger path.",
                    sourceURL: nil,
                    pdfURL: nil
                )
            ),
            tagGenerator: tagger,
            credentialStore: FakeTaggingCredentialStore(apiKey: "sk-test")
        )

        let result = try await service.createPaper(
            from: PaperCaptureRequest(sourceText: "https://example.com/disabled"),
            settings: settings,
            in: context
        )

        XCTAssertNil(result.notice)
        XCTAssertEqual(tagger.callCount, 0)
        XCTAssertTrue(result.paper.tagNames.isEmpty)
    }

    func testAutoTaggingSkipsWhenConfigurationIsIncomplete() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(defaultImportBehavior: .scheduleImmediately, aiTaggingEnabled: true)
        context.insert(settings)
        let tagger = SpyPaperTagger { _, _ in
            XCTFail("Auto tagger should not run when configuration is incomplete")
            return []
        }
        let service = PaperImportService(
            metadataResolver: StubMetadataResolver(
                metadata: ResolvedPaperMetadata(
                    title: "Needs Setup",
                    authors: [],
                    abstractText: "Missing API key path.",
                    sourceURL: nil,
                    pdfURL: nil
                )
            ),
            tagGenerator: tagger,
            credentialStore: FakeTaggingCredentialStore(apiKey: nil)
        )

        let result = try await service.createPaper(
            from: PaperCaptureRequest(sourceText: "https://example.com/needs-setup"),
            settings: settings,
            in: context
        )

        XCTAssertEqual(tagger.callCount, 0)
        XCTAssertEqual(result.notice, "AI auto-tagging is enabled but not fully configured. Imported without generated tags.")
        XCTAssertTrue(result.paper.tagNames.isEmpty)
    }
}
