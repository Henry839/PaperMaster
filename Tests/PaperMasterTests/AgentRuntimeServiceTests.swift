import XCTest
@testable import PaperMaster

final class AgentRuntimeServiceTests: XCTestCase {
    func testDefaultWorkspacePathsUseApplicationSupportSuffixes() {
        let paths = AgentWorkspacePaths.default()

        XCTAssertTrue(paths.rootDirectoryURL.path.hasSuffix("/PaperMaster/AgentWorkspace"))
        XCTAssertEqual(paths.sessionsDirectoryURL.lastPathComponent, "sessions")
        XCTAssertEqual(paths.exportsDirectoryURL.lastPathComponent, "exports")
        XCTAssertEqual(paths.logsDirectoryURL.lastPathComponent, "logs")
        XCTAssertEqual(paths.attachmentsDirectoryURL.lastPathComponent, "attachments")
    }

    func testSearchPapersMatchesLocalLibraryMetadata() {
        let paper = Paper(
            title: "Transformer Interpretability in Practice",
            authors: ["Alice Smith", "Bob Lee"],
            abstractText: "We study activation patching in transformers.",
            status: .inbox,
            tags: Tag.buildList(from: ["interpretability", "llm"])
        )

        let results = AgentToolBridge.searchPapers(query: "patching", in: [paper])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, paper.id)
        XCTAssertEqual(results.first?.tagNames, ["interpretability", "llm"])
    }

    func testProposedQueuePlanUsesSchedulerPlacements() {
        let first = Paper(title: "Paper A", status: .scheduled, queuePosition: 0)
        let second = Paper(title: "Paper B", status: .scheduled, queuePosition: 1)

        let items = AgentToolBridge.proposedQueuePlan(
            papers: [first, second],
            papersPerDay: 1,
            schedulerService: SchedulerService(calendar: Calendar(identifier: .gregorian)),
            referenceDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.queuePosition), [0, 1])
        XCTAssertNotNil(items.first?.dueDate)
        XCTAssertNotNil(items.last?.dueDate)
    }
}
