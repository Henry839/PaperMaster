import XCTest
@testable import PaperReadingScheduler

final class QueueDragPreviewTests: XCTestCase {
    func testReorderedIDsInsertDraggedPaperAfterHoveredRowWhenPointerIsBelowMidpoint() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let fourth = UUID()

        let reorderedIDs = QueueDragPreview.reorderedIDs(
            from: [first, second, third, fourth],
            draggedID: first,
            targetID: third,
            insertAfterTarget: true
        )

        XCTAssertEqual(reorderedIDs, [second, third, first, fourth])
    }

    func testReorderedIDsInsertDraggedPaperBeforeHoveredRowWhenPointerIsAboveMidpoint() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let fourth = UUID()

        let reorderedIDs = QueueDragPreview.reorderedIDs(
            from: [first, second, third, fourth],
            draggedID: fourth,
            targetID: second,
            insertAfterTarget: false
        )

        XCTAssertEqual(reorderedIDs, [first, fourth, second, third])
    }

    func testReorderedIDsAreStableForRepeatedAfterTargetUpdates() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let fourth = UUID()

        let reorderedIDs = QueueDragPreview.reorderedIDs(
            from: [second, third, first, fourth],
            draggedID: first,
            targetID: third,
            insertAfterTarget: true
        )

        XCTAssertNil(reorderedIDs)
    }

    func testReorderedIDsIgnoreDraggedItemAsHoverTarget() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        let reorderedIDs = QueueDragPreview.reorderedIDs(
            from: [first, second, third],
            draggedID: second,
            targetID: second,
            insertAfterTarget: true
        )

        XCTAssertNil(reorderedIDs)
    }
}
