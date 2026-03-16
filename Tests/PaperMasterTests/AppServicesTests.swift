import Foundation
import SwiftData
import XCTest
@testable import PaperMaster

@MainActor
final class AppServicesTests: XCTestCase {
    func testUpdateTagsReplacesPaperTags() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings()
        let paper = Paper(title: "Editable Tags", status: .inbox, autoTaggingStatusMessage: "AI auto-tagging failed: invalid response")
        let existingTag = Tag(name: "old-tag")
        paper.tags = [existingTag]
        context.insert(settings)
        context.insert(existingTag)
        context.insert(paper)

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            reminderService: ReminderService(center: FakeNotificationCenter())
        )

        services.updateTags(
            for: paper,
            tagString: "planning, agents",
            allPapers: [paper],
            settings: settings,
            context: context
        )

        XCTAssertEqual(Set(paper.tagNames), Set(["agents", "planning"]))
        XCTAssertNil(paper.autoTaggingStatusMessage)
    }

    func testGeneratePaperCardPersistsStructuredCardAndHTML() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(aiTaggingEnabled: false)
        let paper = Paper(
            title: "Data Shapley in One Training Run",
            authors: ["Jiachen T. Wang", "Ruoxi Jia"],
            abstractText: "A method for estimating data value during training.",
            status: .scheduled
        )
        context.insert(settings)
        context.insert(paper)

        let exportDirectoryURL = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: exportDirectoryURL) }

        let generator = SpyPaperCardGenerator { input, configuration in
            XCTAssertEqual(configuration.model, "gpt-4o-mini")
            XCTAssertEqual(input.paperTitle, "Data Shapley in One Training Run")
            return PaperCardOutput(
                headline: "用单次训练近似数据贡献",
                venueLine: "ICLR 2025 · oral",
                citationLine: "作者：Jiachen T. Wang, Ruoxi Jia",
                keywords: ["Optimization", "Transformer"],
                sections: [
                    PaperCardSection(id: "summary", title: "论文内容", emoji: "📌", body: "提出 In-Run Data Shapley。"),
                    PaperCardSection(id: "innovation", title: "创新点", emoji: "💡", body: "引入高效近似。"),
                    PaperCardSection(id: "limitations", title: "局限性", emoji: "⚠️", body: "仍有额外计算。")
                ]
            )
        }

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(title: "", authors: [], abstractText: "", sourceURL: nil, pdfURL: nil)
                )
            ),
            paperCardGenerator: generator,
            reminderService: ReminderService(center: FakeNotificationCenter()),
            taggingCredentialStore: FakeTaggingCredentialStore(apiKey: "sk-test"),
            paperCardHTMLDirectoryURL: exportDirectoryURL
        )

        await services.generatePaperCard(
            for: paper,
            settings: settings,
            allPapers: [paper],
            context: context
        )

        let storedPaper = try XCTUnwrap(context.fetch(FetchDescriptor<Paper>()).first)
        let storedCard = try XCTUnwrap(storedPaper.paperCard)
        XCTAssertEqual(storedCard.headline, "用单次训练近似数据贡献")
        XCTAssertEqual(storedCard.sections.count, 3)
        XCTAssertTrue(storedCard.htmlContent.contains("<!doctype html>"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(storedCard.htmlExportURL).path))
        XCTAssertEqual(generator.callCount, 1)
    }

    func testStorageFolderMonitoringImportsExistingPDFs() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let storageDirectoryURL = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectoryURL) }

        let incomingURL = storageDirectoryURL.appendingPathComponent("new-paper.pdf")
        try Data("pdf".utf8).write(to: incomingURL)

        let settings = UserSettings(
            paperStorageMode: .customLocal,
            customPaperStoragePath: storageDirectoryURL.path
        )
        context.insert(settings)

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "Scanned Paper",
                        authors: ["Jane Doe"],
                        abstractText: "Imported from storage watch.",
                        sourceURL: incomingURL,
                        pdfURL: incomingURL
                    )
                )
            ),
            paperStorageService: PaperStorageService(defaultStorageDirectoryURL: storageDirectoryURL),
            reminderService: ReminderService(center: FakeNotificationCenter())
        )

        services.refreshStorageFolderMonitoring(context: context)
        try? await Task.sleep(nanoseconds: 300_000_000)

        let papers = try context.fetch(FetchDescriptor<Paper>())
        XCTAssertEqual(papers.count, 1)
        XCTAssertEqual(papers.first?.title, "Scanned Paper")
        XCTAssertEqual(papers.first?.managedPDFLocalURL?.deletingLastPathComponent().path, storageDirectoryURL.path)
    }

    func testSaveAnnotationCreatesAndDeduplicatesMatchingSelection() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let paper = Paper(title: "Annotated")
        context.insert(paper)

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            reminderService: ReminderService(center: FakeNotificationCenter())
        )
        let selection = try XCTUnwrap(
            ReaderSelectionSnapshot(
                pageIndex: 0,
                quotedText: "A useful sentence",
                rects: [CGRect(x: 12, y: 40, width: 100, height: 16)]
            )
        )

        let first = try XCTUnwrap(
            services.saveAnnotation(for: paper, selection: selection, color: .yellow, context: context)
        )
        let second = try XCTUnwrap(
            services.saveAnnotation(for: paper, selection: selection, color: .pink, context: context)
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.color, .pink)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PaperAnnotation>()), 1)
    }

    func testDeleteAnnotationRemovesHighlight() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let paper = Paper(title: "Annotated")
        context.insert(paper)

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            reminderService: ReminderService(center: FakeNotificationCenter())
        )
        let selection = try XCTUnwrap(
            ReaderSelectionSnapshot(
                pageIndex: 1,
                quotedText: "Delete me",
                rects: [CGRect(x: 4, y: 22, width: 88, height: 12)]
            )
        )
        let annotation = try XCTUnwrap(
            services.saveAnnotation(for: paper, selection: selection, color: .mint, context: context)
        )

        services.deleteAnnotation(annotation, context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PaperAnnotation>()), 0)
    }

    func testAnswerReaderQuestionRequiresConfiguredProviderEvenWhenAutoTaggingIsOff() async throws {
        let settings = UserSettings(aiTaggingEnabled: false)
        let paper = Paper(title: "Annotated")
        let answerer = SpyReaderAnswerer { _, _ in
            XCTFail("Reader answerer should not run without a configured provider")
            return ""
        }
        let selection = try XCTUnwrap(
            ReaderSelectionSnapshot(
                pageIndex: 0,
                quotedText: "Important quote",
                rects: [CGRect(x: 10, y: 22, width: 90, height: 12)]
            )
        )

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            readerAnswerer: answerer,
            reminderService: ReminderService(center: FakeNotificationCenter()),
            taggingCredentialStore: FakeTaggingCredentialStore(apiKey: nil)
        )

        let result = await services.answerReaderQuestion(
            "What does this mean?",
            for: paper,
            selection: selection,
            settings: settings,
            documentContext: .empty
        )

        XCTAssertNil(result)
        XCTAssertEqual(answerer.callCount, 0)
        XCTAssertEqual(services.presentedError?.message, "Save an API key in Keychain to enable AI features.")
    }

    func testAnswerReaderQuestionSurfacesGeneratorUnavailable() async throws {
        let settings = UserSettings(aiTaggingEnabled: false)
        let paper = Paper(title: "Annotated")
        let selection = try XCTUnwrap(
            ReaderSelectionSnapshot(
                pageIndex: 0,
                quotedText: "Important quote",
                rects: [CGRect(x: 10, y: 22, width: 90, height: 12)]
            )
        )

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            reminderService: ReminderService(center: FakeNotificationCenter()),
            taggingCredentialStore: FakeTaggingCredentialStore(apiKey: "sk-test")
        )

        let result = await services.answerReaderQuestion(
            "What does this mean?",
            for: paper,
            selection: selection,
            settings: settings,
            documentContext: .empty
        )

        XCTAssertNil(result)
        XCTAssertEqual(services.presentedError?.message, "Ask AI is not available in this build.")
    }

    func testAnswerReaderQuestionBuildsPayloadWithMetadataAndTruncatedDocumentContext() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(aiTaggingEnabled: false)
        let paper = Paper(
            title: "Transformer Notes",
            authors: ["Author One", "Author Two"],
            abstractText: "This paper studies how transformer scaling changes performance.",
            status: .scheduled
        )
        let firstTag = Tag(name: "nlp")
        let secondTag = Tag(name: "transformers")
        paper.tags = [firstTag, secondTag]
        context.insert(settings)
        context.insert(firstTag)
        context.insert(secondTag)
        context.insert(paper)

        let answerer = SpyReaderAnswerer { input, configuration in
            XCTAssertEqual(configuration.model, "gpt-4o-mini")
            XCTAssertEqual(input.question, "Why does this matter?")
            XCTAssertEqual(input.quotedText, "A useful passage")
            XCTAssertEqual(input.pageNumber, 2)
            XCTAssertEqual(input.paperTitle, "Transformer Notes")
            XCTAssertEqual(input.authorsText, "Author One, Author Two")
            XCTAssertEqual(input.abstractText, "This paper studies how transformer scaling changes performance.")
            XCTAssertEqual(input.tagNames, ["nlp", "transformers"])
            XCTAssertTrue(input.documentWasTruncated)
            XCTAssertEqual(input.documentText, "token token token token token token token token to")
            return "It anchors the paper's central claim."
        }
        let selection = try XCTUnwrap(
            ReaderSelectionSnapshot(
                pageIndex: 1,
                quotedText: "A useful passage",
                rects: [CGRect(x: 12, y: 40, width: 100, height: 16)]
            )
        )

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            readerAnswerer: answerer,
            reminderService: ReminderService(center: FakeNotificationCenter()),
            taggingCredentialStore: FakeTaggingCredentialStore(apiKey: "sk-test")
        )

        let documentContext = ReaderAskAIDocumentContext.make(
            from: String(repeating: "token ", count: 20),
            limit: 50
        )
        let result = await services.answerReaderQuestion(
            "Why does this matter?",
            for: paper,
            selection: selection,
            settings: settings,
            documentContext: documentContext
        )

        XCTAssertEqual(result, "It anchors the paper's central claim.")
        XCTAssertEqual(answerer.callCount, 1)
        XCTAssertNil(services.presentedError)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PaperAnnotation>()), 0)
    }

    func testRequestReaderCompanionCommentPausesWithoutPresentingErrorWhenProviderIsMissing() async throws {
        let settings = UserSettings(aiTaggingEnabled: false)
        let paper = Paper(title: "Annotated")
        let generator = SpyReaderCompanionGenerator { _, _ in
            XCTFail("Reader companion should not run without a configured provider")
            return ReaderCompanionOutput(shouldInterrupt: false, mood: .skeptical, comment: "")
        }

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            readerCompanionGenerator: generator,
            reminderService: ReminderService(center: FakeNotificationCenter()),
            taggingCredentialStore: FakeTaggingCredentialStore(apiKey: nil)
        )

        let result = await services.requestReaderCompanionComment(
            for: paper,
            passage: try focusPassage(pageIndex: 0, text: "Important quote"),
            recentComments: [],
            settings: settings,
            documentContext: .empty
        )

        guard case let .paused(reason) = result else {
            return XCTFail("Expected paused result.")
        }

        XCTAssertEqual(reason.message, "Save an API key in Keychain to enable AI features.")
        XCTAssertEqual(generator.callCount, 0)
        XCTAssertNil(services.presentedError)
    }

    func testRequestReaderCompanionCommentBuildsPayloadWithRecentComments() async throws {
        let settings = UserSettings(aiTaggingEnabled: false)
        let paper = Paper(
            title: "Transformer Notes",
            authors: ["Author One", "Author Two"],
            abstractText: "This paper studies how transformer scaling changes performance.",
            status: .scheduled
        )
        paper.tags = [Tag(name: "nlp"), Tag(name: "transformers")]
        let recentComment = ReaderElfComment(
            passage: try focusPassage(pageIndex: 0, text: "Earlier passage"),
            mood: .skeptical,
            text: "Earlier criticism."
        )

        let generator = SpyReaderCompanionGenerator { input, configuration in
            XCTAssertEqual(configuration.model, "gpt-4o-mini")
            XCTAssertEqual(input.focusPassage.quotedText, "A useful passage")
            XCTAssertEqual(input.paperTitle, "Transformer Notes")
            XCTAssertEqual(input.authorsText, "Author One, Author Two")
            XCTAssertEqual(input.tagNames, ["nlp", "transformers"])
            XCTAssertTrue(input.documentWasTruncated)
            XCTAssertEqual(input.recentComments.map(\.text), ["Earlier criticism."])
            return ReaderCompanionOutput(
                shouldInterrupt: true,
                mood: .skeptical,
                comment: "This claim still outruns the baseline evidence."
            )
        }

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            readerCompanionGenerator: generator,
            reminderService: ReminderService(center: FakeNotificationCenter()),
            taggingCredentialStore: FakeTaggingCredentialStore(apiKey: "sk-test")
        )

        let result = await services.requestReaderCompanionComment(
            for: paper,
            passage: try focusPassage(pageIndex: 1, text: "A useful passage"),
            recentComments: [recentComment],
            settings: settings,
            documentContext: ReaderAskAIDocumentContext.make(from: String(repeating: "token ", count: 20), limit: 50)
        )

        guard case let .comment(output) = result else {
            return XCTFail("Expected comment result.")
        }

        XCTAssertTrue(output.shouldInterrupt)
        XCTAssertEqual(output.comment, "This claim still outruns the baseline evidence.")
        XCTAssertEqual(generator.callCount, 1)
        XCTAssertNil(services.presentedError)
    }

    func testAnswerReaderQuestionStillWorksWhenReaderCompanionGeneratorIsConfigured() async throws {
        let settings = UserSettings(aiTaggingEnabled: false)
        let paper = Paper(title: "Annotated")
        let answerer = SpyReaderAnswerer { _, _ in
            "Reader answer"
        }
        let companionGenerator = SpyReaderCompanionGenerator { _, _ in
            XCTFail("Companion generator should not be used for Ask AI.")
            return ReaderCompanionOutput(shouldInterrupt: false, mood: .skeptical, comment: "")
        }
        let selection = try XCTUnwrap(
            ReaderSelectionSnapshot(
                pageIndex: 0,
                quotedText: "Important quote",
                rects: [CGRect(x: 10, y: 22, width: 90, height: 12)]
            )
        )

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            readerAnswerer: answerer,
            readerCompanionGenerator: companionGenerator,
            reminderService: ReminderService(center: FakeNotificationCenter()),
            taggingCredentialStore: FakeTaggingCredentialStore(apiKey: "sk-test")
        )

        let result = await services.answerReaderQuestion(
            "What does this mean?",
            for: paper,
            selection: selection,
            settings: settings,
            documentContext: .empty
        )

        XCTAssertEqual(result, "Reader answer")
        XCTAssertEqual(answerer.callCount, 1)
        XCTAssertEqual(companionGenerator.callCount, 0)
    }

    func testDuplicateImportReturnsExistingPaperWithoutMutatingQueue() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(defaultImportBehavior: .scheduleImmediately)
        let existingPaper = Paper(
            title: "Queued Paper",
            sourceURL: URL(string: "https://arxiv.org/abs/2603.06028"),
            pdfURL: URL(string: "https://arxiv.org/pdf/2603.06028v1.pdf"),
            status: .scheduled,
            queuePosition: 0
        )
        context.insert(settings)
        context.insert(existingPaper)

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "Queued Paper",
                        authors: [],
                        abstractText: "",
                        sourceURL: URL(string: "https://arxiv.org/abs/2603.06028"),
                        pdfURL: URL(string: "https://arxiv.org/pdf/2603.06028v1.pdf")
                    )
                )
            ),
            reminderService: ReminderService(center: FakeNotificationCenter())
        )

        let returnedPaper = await services.importPaper(
            request: PaperCaptureRequest(sourceText: "https://arxiv.org/pdf/2603.06028v1.pdf"),
            settings: settings,
            currentPapers: [existingPaper],
            in: context
        )

        XCTAssertEqual(returnedPaper?.id, existingPaper.id)
        XCTAssertEqual(existingPaper.queuePosition, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Paper>()), 1)
    }

    private func focusPassage(pageIndex: Int, text: String) throws -> ReaderFocusPassageSnapshot {
        try XCTUnwrap(
            ReaderFocusPassageSnapshot(
                pageIndex: pageIndex,
                quotedText: text,
                rects: [ReaderAnnotationRect(rect: CGRect(x: 10, y: 22, width: 90, height: 12))],
                source: .viewport
            )
        )
    }

    func testImportStoresManagedPDFInDefaultLocalStorage() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(defaultImportBehavior: .scheduleImmediately)
        context.insert(settings)

        let storageDirectoryURL = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectoryURL) }

        let pdfURL = URL(string: "https://example.com/managed-paper.pdf")!
        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "Managed Paper",
                        authors: [],
                        abstractText: "",
                        sourceURL: pdfURL,
                        pdfURL: pdfURL
                    )
                )
            ),
            paperStorageService: PaperStorageService(
                networking: StubNetworking { url in
                    XCTAssertEqual(url, pdfURL)
                    return (Data("pdf-data".utf8), TestSupport.httpResponse(url: url))
                },
                credentialStore: FakePaperStorageCredentialStore(),
                defaultStorageDirectoryURL: storageDirectoryURL
            ),
            reminderService: ReminderService(center: FakeNotificationCenter())
        )

        let paper = await services.importPaper(
            request: PaperCaptureRequest(sourceText: pdfURL.absoluteString),
            settings: settings,
            currentPapers: [],
            in: context
        )

        XCTAssertEqual(paper?.managedPDFLocalURL?.deletingLastPathComponent().path, storageDirectoryURL.path)
        XCTAssertNil(paper?.managedPDFRemoteURL)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(paper?.managedPDFLocalURL)), Data("pdf-data".utf8))
    }

    func testImportKeepsPaperWhenManagedStorageFails() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(
            defaultImportBehavior: .scheduleImmediately,
            paperStorageMode: .remoteSSH,
            remotePaperStorageHost: "example.com",
            remotePaperStoragePort: 22,
            remotePaperStorageUsername: "reader",
            remotePaperStorageDirectory: "/papers"
        )
        context.insert(settings)

        let pdfURL = URL(string: "https://example.com/needs-storage.pdf")!
        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "Needs Storage",
                        authors: [],
                        abstractText: "",
                        sourceURL: pdfURL,
                        pdfURL: pdfURL
                    )
                )
            ),
            paperStorageService: PaperStorageService(
                networking: StubNetworking { url in
                    XCTAssertEqual(url, pdfURL)
                    return (Data("pdf-data".utf8), TestSupport.httpResponse(url: url))
                },
                credentialStore: FakePaperStorageCredentialStore()
            ),
            reminderService: ReminderService(center: FakeNotificationCenter())
        )

        let paper = await services.importPaper(
            request: PaperCaptureRequest(sourceText: pdfURL.absoluteString),
            settings: settings,
            currentPapers: [],
            in: context
        )

        XCTAssertNotNil(paper)
        XCTAssertNil(paper?.managedPDFLocalURL)
        XCTAssertNil(paper?.managedPDFRemoteURL)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Paper>()), 1)
        XCTAssertTrue(services.presentedNotice?.message.contains("Managed PDF storage failed.") == true)
    }

    func testCopyTextWritesToClipboardAndShowsNotice() {
        let clipboard = FakeTextClipboard()
        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            reminderService: ReminderService(center: FakeNotificationCenter()),
            textClipboard: clipboard
        )

        services.copyText("@article{test}", notice: "Copied BibTeX.")

        XCTAssertEqual(clipboard.lastCopiedString, "@article{test}")
        XCTAssertEqual(services.presentedNotice?.message, "Copied BibTeX.")
    }

    func testFusePapersReturnsIdeasAndShowsNotice() async {
        let settings = UserSettings(aiTaggingEnabled: false)
        let first = Paper(title: "Search Paper", abstractText: "Search abstract", status: .scheduled)
        let second = Paper(title: "Agent Paper", abstractText: "Agent abstract", status: .scheduled)
        let expectedModel = settings.aiTaggingModel
        let fusionGenerator = SpyPaperFusionGenerator { inputs, configuration in
            XCTAssertEqual(inputs.count, 2)
            XCTAssertEqual(configuration.model, expectedModel)
            return [
                PaperFusionIdea(title: "Idea 1", hypothesis: "Hypothesis 1", rationale: "Rationale 1"),
                PaperFusionIdea(title: "Idea 2", hypothesis: "Hypothesis 2", rationale: "Rationale 2"),
                PaperFusionIdea(title: "Idea 3", hypothesis: "Hypothesis 3", rationale: "Rationale 3")
            ]
        }

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            fusionGenerator: fusionGenerator,
            reminderService: ReminderService(center: FakeNotificationCenter()),
            taggingCredentialStore: FakeTaggingCredentialStore(apiKey: "sk-test")
        )

        let result = await services.fusePapers([first, second], settings: settings)

        XCTAssertEqual(result?.ideas.count, 3)
        XCTAssertEqual(fusionGenerator.callCount, 1)
        XCTAssertEqual(services.presentedNotice?.message, "Refining complete. The reactor returned 3 research ideas.")
        XCTAssertNil(services.presentedError)
    }

    func testFusePapersRequiresConfiguredProviderEvenWhenAutoTaggingIsOff() async {
        let settings = UserSettings(aiTaggingEnabled: false)
        let first = Paper(title: "Search Paper", status: .scheduled)
        let second = Paper(title: "Agent Paper", status: .scheduled)
        let fusionGenerator = SpyPaperFusionGenerator { _, _ in
            XCTFail("Fusion generator should not run without a configured provider")
            return []
        }

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            fusionGenerator: fusionGenerator,
            reminderService: ReminderService(center: FakeNotificationCenter()),
            taggingCredentialStore: FakeTaggingCredentialStore(apiKey: nil)
        )

        let result = await services.fusePapers([first, second], settings: settings)

        XCTAssertNil(result)
        XCTAssertEqual(fusionGenerator.callCount, 0)
        XCTAssertEqual(services.presentedError?.message, "Save an API key in Keychain to enable AI features.")
    }

    func testFusePapersPropagatesProviderFailure() async {
        let settings = UserSettings(aiTaggingEnabled: false)
        let first = Paper(title: "Search Paper", status: .scheduled)
        let second = Paper(title: "Agent Paper", status: .scheduled)
        let fusionGenerator = SpyPaperFusionGenerator { _, _ in
            throw TestError(message: "Provider unavailable")
        }

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            fusionGenerator: fusionGenerator,
            reminderService: ReminderService(center: FakeNotificationCenter()),
            taggingCredentialStore: FakeTaggingCredentialStore(apiKey: "sk-test")
        )

        let result = await services.fusePapers([first, second], settings: settings)

        XCTAssertNil(result)
        XCTAssertEqual(fusionGenerator.callCount, 1)
        XCTAssertEqual(services.presentedError?.message, "Provider unavailable")
    }

    func testFusePapersRequiresAtLeastTwoPapers() async {
        let settings = UserSettings(aiTaggingEnabled: false)
        let onlyPaper = Paper(title: "Lonely Paper", status: .scheduled)
        let fusionGenerator = SpyPaperFusionGenerator { _, _ in
            XCTFail("Fusion generator should not run with fewer than two papers")
            return []
        }

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            fusionGenerator: fusionGenerator,
            reminderService: ReminderService(center: FakeNotificationCenter()),
            taggingCredentialStore: FakeTaggingCredentialStore(apiKey: "sk-test")
        )

        let result = await services.fusePapers([onlyPaper], settings: settings)

        XCTAssertNil(result)
        XCTAssertEqual(fusionGenerator.callCount, 0)
        XCTAssertEqual(services.presentedError?.message, "Add at least two papers to the reactor before refining.")
    }

    func testPrepareReaderPrefersManagedLocalPDF() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings()
        let managedDirectoryURL = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: managedDirectoryURL) }

        let managedPDFURL = managedDirectoryURL.appendingPathComponent("managed.pdf")
        try Data("managed".utf8).write(to: managedPDFURL)

        let paper = Paper(
            title: "Managed Local",
            pdfURL: URL(string: "https://example.com/original.pdf"),
            managedPDFLocalPath: managedPDFURL.path,
            status: .scheduled
        )
        context.insert(settings)
        context.insert(paper)

        let services = makeServices()

        let presentation = await services.prepareReader(
            for: paper,
            currentPapers: [paper],
            settings: settings,
            context: context
        )

        XCTAssertEqual(presentation?.fileURL.path, managedPDFURL.path)
        XCTAssertNil(paper.cachedPDFURL)
    }

    func testMoveToEarlierQueueIndexReordersQueueAndClearsMovedOverride() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(papersPerDay: 1)
        let first = Paper(title: "First", status: .scheduled, queuePosition: 0)
        let moved = Paper(
            title: "Moved",
            status: .scheduled,
            queuePosition: 1,
            manualDueDateOverride: TestSupport.reminderDate(hour: 13, minute: 0)
        )
        let third = Paper(title: "Third", status: .reading, queuePosition: 2)
        let inbox = Paper(title: "Inbox", status: .inbox, queuePosition: 99)

        context.insert(settings)
        context.insert(first)
        context.insert(moved)
        context.insert(third)
        context.insert(inbox)

        let services = makeServices()

        services.move(
            paper: moved,
            toQueueIndex: 0,
            allPapers: [first, moved, third, inbox],
            settings: settings,
            context: context
        )

        let queue = [first, moved, third].sorted { $0.queuePosition < $1.queuePosition }
        XCTAssertEqual(queue.map(\.id), [moved.id, first.id, third.id])
        XCTAssertEqual(queue.map(\.queuePosition), [0, 1, 2])
        XCTAssertNil(moved.manualDueDateOverride)
    }

    func testMoveToLaterQueueIndexRewritesQueuePositionsContiguously() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(papersPerDay: 1)
        let first = Paper(title: "First", status: .scheduled, queuePosition: 0)
        let second = Paper(title: "Second", status: .scheduled, queuePosition: 1)
        let third = Paper(title: "Third", status: .scheduled, queuePosition: 2)
        let fourth = Paper(title: "Fourth", status: .reading, queuePosition: 3)

        context.insert(settings)
        context.insert(first)
        context.insert(second)
        context.insert(third)
        context.insert(fourth)

        let services = makeServices()

        services.move(
            paper: first,
            toQueueIndex: 2,
            allPapers: [first, second, third, fourth],
            settings: settings,
            context: context
        )

        let queue = [first, second, third, fourth].sorted { $0.queuePosition < $1.queuePosition }
        XCTAssertEqual(queue.map(\.id), [second.id, third.id, first.id, fourth.id])
        XCTAssertEqual(queue.map(\.queuePosition), [0, 1, 2, 3])
    }

    func testMoveToQueueIndexAtBoundsIsNoOp() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(papersPerDay: 1)
        let topOverride = TestSupport.reminderDate(hour: 10, minute: 0)
        let bottomOverride = TestSupport.reminderDate(hour: 16, minute: 0)
        let first = Paper(
            title: "First",
            status: .scheduled,
            queuePosition: 0,
            manualDueDateOverride: topOverride
        )
        let second = Paper(title: "Second", status: .scheduled, queuePosition: 1)
        let third = Paper(
            title: "Third",
            status: .reading,
            queuePosition: 2,
            manualDueDateOverride: bottomOverride
        )

        context.insert(settings)
        context.insert(first)
        context.insert(second)
        context.insert(third)

        let services = makeServices()

        services.move(
            paper: first,
            toQueueIndex: -5,
            allPapers: [first, second, third],
            settings: settings,
            context: context
        )
        services.move(
            paper: third,
            toQueueIndex: 99,
            allPapers: [first, second, third],
            settings: settings,
            context: context
        )

        let queue = [first, second, third].sorted { $0.queuePosition < $1.queuePosition }
        XCTAssertEqual(queue.map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(queue.map(\.queuePosition), [0, 1, 2])
        XCTAssertEqual(first.manualDueDateOverride, topOverride)
        XCTAssertEqual(third.manualDueDateOverride, bottomOverride)
    }

    func testReplanQueueFromTodayRedistributesOverdueScheduledPapers() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(papersPerDay: 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 9))!
        let today = calendar.startOfDay(for: referenceDate)
        let overdueFirst = Paper(
            title: "Overdue First",
            status: .scheduled,
            queuePosition: 0,
            dueDate: calendar.date(byAdding: .day, value: -2, to: today)
        )
        let overdueSecond = Paper(
            title: "Overdue Second",
            status: .scheduled,
            queuePosition: 1,
            dueDate: calendar.date(byAdding: .day, value: -1, to: today)
        )
        let future = Paper(
            title: "Future",
            status: .scheduled,
            queuePosition: 2,
            dueDate: calendar.date(byAdding: .day, value: 4, to: today)
        )
        let reading = Paper(
            title: "Reading",
            status: .reading,
            queuePosition: 3,
            dueDate: calendar.date(byAdding: .day, value: -3, to: today)
        )

        context.insert(settings)
        context.insert(overdueFirst)
        context.insert(overdueSecond)
        context.insert(future)
        context.insert(reading)

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            schedulerService: SchedulerService(calendar: calendar),
            reminderService: ReminderService(center: FakeNotificationCenter())
        )

        services.replanQueueFromToday(
            papers: [overdueFirst, overdueSecond, future, reading],
            settings: settings,
            context: context,
            referenceDate: referenceDate
        )

        XCTAssertEqual(overdueFirst.dueDate, today)
        XCTAssertEqual(overdueSecond.dueDate, calendar.date(byAdding: .day, value: 1, to: today))
        XCTAssertEqual(future.dueDate, calendar.date(byAdding: .day, value: 2, to: today))
        XCTAssertEqual(reading.dueDate, calendar.date(byAdding: .day, value: -3, to: today))
        XCTAssertEqual(services.presentedNotice?.message, "Replanned 2 overdue papers from today.")
    }

    func testQueueReorderTagEditAndDeleteRemainStableWithOverlappingTagNames() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(papersPerDay: 1)
        let first = Paper(
            title: "First",
            status: .scheduled,
            queuePosition: 0,
            tags: Tag.buildList(from: ["agents"])
        )
        let second = Paper(
            title: "Second",
            status: .scheduled,
            queuePosition: 1,
            tags: Tag.buildList(from: ["agents"])
        )

        context.insert(settings)
        context.insert(first)
        context.insert(second)
        try context.save()

        let services = makeServices()

        services.move(
            paper: second,
            toQueueIndex: 0,
            allPapers: [first, second],
            settings: settings,
            context: context
        )
        services.updateTags(
            for: first,
            tagString: "agents, planning",
            allPapers: [first, second],
            settings: settings,
            context: context
        )
        await services.delete(
            paper: second,
            allPapers: [first, second],
            settings: settings,
            context: context
        )

        let storedPapers = try context.fetch(FetchDescriptor<Paper>())
        let storedTags = try context.fetch(FetchDescriptor<Tag>())

        XCTAssertEqual(storedPapers.map(\.id), [first.id])
        XCTAssertEqual(first.queuePosition, 0)
        XCTAssertEqual(Set(first.tagNames), Set(["agents", "planning"]))
        XCTAssertEqual(storedTags.count, 2)
        XCTAssertEqual(Set(storedTags.map(\.name)), Set(["agents", "planning"]))
        XCTAssertTrue(storedTags.allSatisfy { $0.paper?.id == first.id })
    }

    func testDeleteRemovesPaperEvenWhenManagedRemoteCleanupFails() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings()
        let paper = Paper(
            title: "Remote Managed",
            managedPDFRemoteURLString: "sftp://reader@example.com:22/papers/remote-managed.pdf",
            status: .scheduled
        )

        let credentialStore = FakePaperStorageCredentialStore(
            storedPasswords: [
                PaperStorageRemoteEndpoint(host: "example.com", port: 22, username: "reader"): "secret"
            ]
        )
        let commandRunner = RecordingCommandRunner()
        commandRunner.error = CommandRunnerError.nonZeroExit(
            executablePath: "/usr/bin/sftp",
            status: 1,
            standardError: "permission denied"
        )

        context.insert(settings)
        context.insert(paper)

        let services = AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            paperStorageService: PaperStorageService(
                credentialStore: credentialStore,
                commandRunner: commandRunner
            ),
            reminderService: ReminderService(center: FakeNotificationCenter())
        )

        await services.delete(
            paper: paper,
            allPapers: [paper],
            settings: settings,
            context: context
        )

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Paper>()), 0)
        XCTAssertEqual(commandRunner.invocations.count, 1)
    }

    private func makeServices() -> AppServices {
        AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            reminderService: ReminderService(center: FakeNotificationCenter())
        )
    }
}
