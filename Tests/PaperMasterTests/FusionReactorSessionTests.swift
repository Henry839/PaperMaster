import XCTest
@testable import PaperMaster

@MainActor
final class FusionReactorSessionTests: XCTestCase {
    func testAddMaterialIgnoresDuplicates() {
        let session = FusionReactorSession()
        let paperID = UUID()

        XCTAssertEqual(session.addMaterial(paperID), .added)
        XCTAssertEqual(session.addMaterial(paperID), .duplicate)
        XCTAssertEqual(session.selectedPaperIDs, [paperID])
    }

    func testAddMaterialEnforcesMaximumCapacity() {
        let session = FusionReactorSession()

        for _ in 0..<FusionMaterialSelection.maximumPaperCount {
            XCTAssertEqual(session.addMaterial(UUID()), .added)
        }

        XCTAssertEqual(session.addMaterial(UUID()), .limitReached)
        XCTAssertEqual(session.selectedPaperIDs.count, FusionMaterialSelection.maximumPaperCount)
    }

    func testResetClearsSelectionAndResults() {
        let session = FusionReactorSession()
        let paperID = UUID()
        _ = session.addMaterial(paperID)
        session.beginFusion()
        session.finishFusion(
            with: PaperFusionResult(
                selectedPaperIDs: [paperID, UUID()],
                ideas: [
                    PaperFusionIdea(
                        title: "Idea",
                        hypothesis: "Hypothesis",
                        rationale: "Rationale"
                    )
                ],
                generatedAt: .now
            )
        )

        session.reset()

        XCTAssertTrue(session.selectedPaperIDs.isEmpty)
        XCTAssertNil(session.result)
        XCTAssertFalse(session.isFusing)
    }

    func testSyncMaterialsRemovesMissingPaperIDs() {
        let session = FusionReactorSession()
        let retainedID = UUID()
        let removedID = UUID()
        _ = session.addMaterial(retainedID)
        _ = session.addMaterial(removedID)

        session.syncMaterials(allowedPaperIDs: Set([retainedID]))

        XCTAssertEqual(session.selectedPaperIDs, [retainedID])
    }
}
