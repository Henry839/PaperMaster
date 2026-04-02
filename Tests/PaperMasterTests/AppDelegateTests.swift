import XCTest
@testable import PaperMasterShared

@MainActor
final class AppDelegateTests: XCTestCase {
    func testHandleReopenRestoresHiddenWindowWithoutCreatingNewWindow() {
        var restoredWindowIDs: [String] = []
        var reopenedCount = 0
        var activationCount = 0
        let coordinator = AppDockReopenCoordinator(
            windowTargets: {
                [
                    .init(
                        isVisible: false,
                        restore: {
                            restoredWindowIDs.append("main")
                        }
                    )
                ]
            },
            reopenMainWindow: {
                reopenedCount += 1
            },
            activateApp: {
                activationCount += 1
            }
        )

        let handled = coordinator.handleReopen(hasVisibleWindows: false)

        XCTAssertTrue(handled)
        XCTAssertEqual(restoredWindowIDs, ["main"])
        XCTAssertEqual(reopenedCount, 0)
        XCTAssertEqual(activationCount, 1)
    }

    func testHandleReopenCreatesWindowWhenNoWindowExists() {
        var reopenedCount = 0
        var activationCount = 0
        let coordinator = AppDockReopenCoordinator(
            windowTargets: { [] },
            reopenMainWindow: {
                reopenedCount += 1
            },
            activateApp: {
                activationCount += 1
            }
        )

        let handled = coordinator.handleReopen(hasVisibleWindows: false)

        XCTAssertTrue(handled)
        XCTAssertEqual(reopenedCount, 1)
        XCTAssertEqual(activationCount, 1)
    }

    func testHandleReopenDoesNothingWhenWindowsAreAlreadyVisible() {
        var restoredCount = 0
        var reopenedCount = 0
        var activationCount = 0
        let coordinator = AppDockReopenCoordinator(
            windowTargets: {
                [
                    .init(
                        isVisible: true,
                        restore: {
                            restoredCount += 1
                        }
                    )
                ]
            },
            reopenMainWindow: {
                reopenedCount += 1
            },
            activateApp: {
                activationCount += 1
            }
        )

        let handled = coordinator.handleReopen(hasVisibleWindows: true)

        XCTAssertFalse(handled)
        XCTAssertEqual(restoredCount, 0)
        XCTAssertEqual(reopenedCount, 0)
        XCTAssertEqual(activationCount, 0)
    }
}
