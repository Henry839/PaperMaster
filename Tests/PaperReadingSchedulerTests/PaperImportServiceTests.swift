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
        XCTAssertNil(paper.venueKey)
        XCTAssertNil(paper.venueName)
        XCTAssertNil(paper.doi)
        XCTAssertNil(paper.bibtex)
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
        XCTAssertNil(paper.venueKey)
        XCTAssertNil(paper.venueName)
        XCTAssertNil(paper.bibtex)
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
        XCTAssertEqual(result.paper.autoTaggingStatusMessage, "AI auto-tagging failed: Provider unavailable")
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
        XCTAssertEqual(result.paper.autoTaggingStatusMessage, "AI auto-tagging is enabled but not fully configured. Imported without generated tags.")
    }

    func testDuplicateDirectPDFImportReturnsExistingPaper() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(defaultImportBehavior: .scheduleImmediately)
        let existingPaper = Paper(
            title: "Agentic Workflows",
            sourceURL: URL(string: "https://example.com/readings/agentic-workflows.pdf"),
            pdfURL: URL(string: "https://example.com/readings/agentic-workflows.pdf"),
            status: .scheduled
        )
        context.insert(settings)
        context.insert(existingPaper)

        let service = PaperImportService(
            metadataResolver: StubMetadataResolver(
                metadata: ResolvedPaperMetadata(
                    title: "Agentic Workflows",
                    authors: [],
                    abstractText: "",
                    sourceURL: URL(string: "https://example.com/readings/agentic-workflows.pdf"),
                    pdfURL: URL(string: "https://example.com/readings/agentic-workflows.pdf")
                )
            )
        )

        let result = try await service.createPaper(
            from: PaperCaptureRequest(sourceText: "https://example.com/readings/agentic-workflows.pdf"),
            settings: settings,
            in: context
        )

        XCTAssertFalse(result.didCreatePaper)
        XCTAssertEqual(result.paper.id, existingPaper.id)
        XCTAssertEqual(result.notice, "That paper is already in your library.")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Paper>()), 1)
    }

    func testDuplicateArxivAbsAndPDFImportReturnSameExistingPaper() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(defaultImportBehavior: .scheduleImmediately)
        let existingPaper = Paper(
            title: "Compression Based Classification",
            sourceURL: URL(string: "https://arxiv.org/abs/2603.06359"),
            pdfURL: URL(string: "https://arxiv.org/pdf/2603.06359v1.pdf"),
            status: .scheduled
        )
        context.insert(settings)
        context.insert(existingPaper)

        let service = PaperImportService(
            metadataResolver: StubMetadataResolver(
                metadata: ResolvedPaperMetadata(
                    title: "Compression Based Classification",
                    authors: [],
                    abstractText: "A paper about classification.",
                    sourceURL: URL(string: "https://arxiv.org/abs/2603.06359"),
                    pdfURL: URL(string: "https://arxiv.org/pdf/2603.06359v1.pdf")
                )
            )
        )

        let result = try await service.createPaper(
            from: PaperCaptureRequest(sourceText: "https://arxiv.org/pdf/2603.06359v1.pdf"),
            settings: settings,
            in: context
        )

        XCTAssertFalse(result.didCreatePaper)
        XCTAssertEqual(result.paper.id, existingPaper.id)
        XCTAssertEqual(result.notice, "That paper is already in your library.")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Paper>()), 1)
    }

    func testArxivImportStoresPublishedVenueAndGeneratedBibTeX() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(defaultImportBehavior: .scheduleImmediately)
        context.insert(settings)
        let enricher = SpyPublicationEnricher { request in
            XCTAssertEqual(request.arxivID, "2401.00001")
            XCTAssertEqual(request.doi, "10.1000/test-doi")
            return PublicationEnrichmentResult(
                venueKey: "CVPR",
                venueName: "Conference on Computer Vision and Pattern Recognition (CVPR)",
                doi: "10.1000/test-doi",
                bibtex: """
                @inproceedings{doe2026planning,
                  title = {Planning with Language Models},
                  author = {Jane Doe and John Roe},
                  year = {2026},
                  booktitle = CVPR
                }
                """
            )
        }
        let service = PaperImportService(
            metadataResolver: StubMetadataResolver(
                metadata: ResolvedPaperMetadata(
                    title: "Planning with Language Models",
                    authors: ["Jane Doe", "John Roe"],
                    abstractText: "A compact abstract for testing.",
                    arxivID: "2401.00001",
                    doi: "10.1000/test-doi",
                    publishedYear: 2026,
                    sourceURL: URL(string: "https://arxiv.org/abs/2401.00001"),
                    pdfURL: URL(string: "https://arxiv.org/pdf/2401.00001.pdf")
                )
            ),
            publicationEnricher: enricher
        )

        let result = try await service.createPaper(
            from: PaperCaptureRequest(sourceText: "https://arxiv.org/abs/2401.00001"),
            settings: settings,
            in: context
        )

        XCTAssertEqual(result.paper.venueKey, "CVPR")
        XCTAssertEqual(result.paper.venueName, "Conference on Computer Vision and Pattern Recognition (CVPR)")
        XCTAssertEqual(result.paper.doi, "10.1000/test-doi")
        XCTAssertEqual(result.paper.bibtex?.contains("booktitle = CVPR"), true)
        XCTAssertEqual(enricher.callCount, 1)
    }

    func testArxivImportLeavesVenueBlankAndStoresArxivBibTeXWhenPublicationIsUnverified() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(defaultImportBehavior: .scheduleImmediately)
        context.insert(settings)
        let service = PaperImportService(
            metadataResolver: StubMetadataResolver(
                metadata: ResolvedPaperMetadata(
                    title: "When AI Levels the Playing Field",
                    authors: ["Xupeng Chen", "Shuchen Meng"],
                    abstractText: "Economics paper.",
                    arxivID: "2603.05565",
                    publishedYear: 2026,
                    sourceURL: URL(string: "https://arxiv.org/abs/2603.05565"),
                    pdfURL: URL(string: "https://arxiv.org/pdf/2603.05565.pdf")
                )
            ),
            publicationEnricher: SpyPublicationEnricher { _ in
                PublicationEnrichmentResult(
                    venueKey: nil,
                    venueName: nil,
                    doi: nil,
                    bibtex: """
                    @misc{chen2026playingfield,
                      title = {When AI Levels the Playing Field},
                      author = {Xupeng Chen and Shuchen Meng},
                      year = {2026}
                    }
                    """
                )
            }
        )

        let result = try await service.createPaper(
            from: PaperCaptureRequest(sourceText: "https://arxiv.org/abs/2603.05565"),
            settings: settings,
            in: context
        )

        XCTAssertNil(result.paper.venueKey)
        XCTAssertNil(result.paper.venueName)
        XCTAssertEqual(result.paper.bibtex?.contains("@misc"), true)
    }

    func testDuplicateArxivImportDoesNotTriggerPublicationEnrichment() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(defaultImportBehavior: .scheduleImmediately)
        let existingPaper = Paper(
            title: "Existing",
            sourceURL: URL(string: "https://arxiv.org/abs/2603.05565"),
            pdfURL: URL(string: "https://arxiv.org/pdf/2603.05565v1.pdf"),
            status: .scheduled
        )
        context.insert(settings)
        context.insert(existingPaper)
        let enricher = SpyPublicationEnricher { _ in
            XCTFail("Publication enrichment should not run for duplicates")
            return PublicationEnrichmentResult()
        }
        let service = PaperImportService(
            metadataResolver: StubMetadataResolver(
                metadata: ResolvedPaperMetadata(
                    title: "Existing",
                    authors: ["Jane Doe"],
                    abstractText: "",
                    arxivID: "2603.05565",
                    sourceURL: URL(string: "https://arxiv.org/abs/2603.05565"),
                    pdfURL: URL(string: "https://arxiv.org/pdf/2603.05565v1.pdf")
                )
            ),
            publicationEnricher: enricher
        )

        let result = try await service.createPaper(
            from: PaperCaptureRequest(sourceText: "https://arxiv.org/abs/2603.05565"),
            settings: settings,
            in: context
        )

        XCTAssertFalse(result.didCreatePaper)
        XCTAssertEqual(enricher.callCount, 0)
    }
}
