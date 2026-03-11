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
