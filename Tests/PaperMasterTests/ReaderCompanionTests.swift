import AppKit
import CoreGraphics
import XCTest
@testable import PaperMaster

final class ReaderCompanionTests: XCTestCase {
    func testSessionCapsRecentCommentsAndKeepsNewestFirst() throws {
        var session = ReaderElfSessionState()

        for index in 0..<6 {
            let comment = ReaderElfComment(
                passage: try passage(pageIndex: index, text: "Passage \(index)"),
                mood: .skeptical,
                text: "Comment \(index)",
                createdAt: Date(timeIntervalSince1970: Double(index))
            )
            session.surface(comment, cooldown: 0)
        }

        XCTAssertEqual(session.recentComments.count, 5)
        XCTAssertEqual(session.recentComments.first?.text, "Comment 5")
        XCTAssertEqual(session.recentComments.last?.text, "Comment 1")
    }

    func testSessionDoesNotEvaluateSamePassageTwiceInARow() throws {
        var session = ReaderElfSessionState()
        let firstPassage = try passage(pageIndex: 0, text: "A method claim")
        let secondPassage = try passage(pageIndex: 0, text: "A different baseline claim")

        session.finishWithoutComment(for: firstPassage)

        XCTAssertFalse(session.canEvaluate(firstPassage))
        XCTAssertTrue(session.canEvaluate(secondPassage))
    }

    func testSessionReportsCooldownStatusUntilDeadline() throws {
        var session = ReaderElfSessionState()
        let createdAt = Date(timeIntervalSince1970: 100)
        let comment = ReaderElfComment(
            passage: try passage(pageIndex: 0, text: "A weak ablation"),
            mood: .alarmed,
            text: "This control looks missing.",
            createdAt: createdAt
        )

        session.surface(comment, cooldown: 45)

        guard case let .coolingDown(until) = session.status(now: createdAt.addingTimeInterval(10)) else {
            return XCTFail("Expected cooldown status.")
        }

        XCTAssertEqual(until, createdAt.addingTimeInterval(45))
        XCTAssertEqual(session.status(now: createdAt.addingTimeInterval(46)), .listening)
    }

    func testSessionDoesNotEvaluateWhileActiveCommentIsUntappedEvenAfterCooldownExpires() throws {
        var session = ReaderElfSessionState()
        let activeComment = ReaderElfComment(
            passage: try passage(pageIndex: 0, text: "An underpowered baseline"),
            mood: .skeptical,
            text: "This comparison still feels soft.",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let nextPassage = try passage(pageIndex: 0, text: "A different paragraph")

        session.surface(activeComment, cooldown: 45)

        XCTAssertFalse(session.canEvaluate(nextPassage, now: Date(timeIntervalSince1970: 200)))

        session.dismissActiveComment()

        XCTAssertTrue(session.canEvaluate(nextPassage, now: Date(timeIntervalSince1970: 200)))
    }

    func testClusteredLinesStopAtLargeParagraphGap() {
        let lines = [
            line(text: "First line", x: 40, y: 680, width: 260, height: 14),
            line(text: "Second line", x: 42, y: 660, width: 256, height: 14),
            line(text: "Paragraph two", x: 40, y: 600, width: 260, height: 14)
        ]

        let clustered = ReaderFocusPassageExtractor.clusteredLines(around: 1, lines: lines)

        XCTAssertEqual(clustered.map(\.text), ["First line", "Second line"])
    }

    func testFallbackLinesReturnLocalWindowAroundCenter() {
        let lines = [
            line(text: "L0", x: 40, y: 700, width: 260, height: 14),
            line(text: "L1", x: 40, y: 680, width: 260, height: 14),
            line(text: "L2", x: 40, y: 660, width: 260, height: 14),
            line(text: "L3", x: 40, y: 640, width: 260, height: 14),
            line(text: "L4", x: 40, y: 620, width: 260, height: 14),
            line(text: "L5", x: 40, y: 600, width: 260, height: 14)
        ]

        let fallback = ReaderFocusPassageExtractor.fallbackLines(around: 2, lines: lines)

        XCTAssertEqual(fallback.map(\.text), ["L0", "L1", "L2", "L3", "L4"])
    }

    func testPassageJumpTargetBuildsUnionTargetRectFromAllPassageLines() {
        let target = ReaderPassageJumpTarget(
            pageIndex: 2,
            rects: [
                ReaderAnnotationRect(rect: CGRect(x: 48, y: 420, width: 180, height: 18)),
                ReaderAnnotationRect(rect: CGRect(x: 52, y: 394, width: 168, height: 18)),
                ReaderAnnotationRect(rect: CGRect(x: 50, y: 368, width: 172, height: 18))
            ]
        )

        assertRectEqual(
            target.targetRect,
            CGRect(x: 48, y: 368, width: 180, height: 70)
        )
    }

    func testPassageJumpTargetScrollRectExpandsTargetWithConfiguredPadding() {
        let target = ReaderPassageJumpTarget(
            pageIndex: 0,
            rects: [ReaderAnnotationRect(rect: CGRect(x: 80, y: 260, width: 140, height: 20))]
        )

        let scrollRect = target.scrollRect
        assertRectEqual(
            scrollRect,
            CGRect(
                x: 80 - ReaderPassageJumpTarget.scrollHorizontalPadding,
                y: 260 - ReaderPassageJumpTarget.scrollVerticalPadding,
                width: 140 + (ReaderPassageJumpTarget.scrollHorizontalPadding * 2),
                height: 20 + (ReaderPassageJumpTarget.scrollVerticalPadding * 2)
            )
        )
        XCTAssertGreaterThan(ReaderPassageJumpTarget.scrollVerticalPadding, ReaderPassageJumpTarget.scrollHorizontalPadding)
    }

    func testOverlayLayoutPrefersAbovePlacementWhenThereIsRoom() throws {
        let geometry = geometry(
            paneBounds: CGRect(x: 0, y: 0, width: 920, height: 720),
            pageFrame: CGRect(x: 170, y: 48, width: 470, height: 610),
            anchorFrame: CGRect(x: 320, y: 318, width: 120, height: 40),
            passageLineFrames: [
                CGRect(x: 320, y: 318, width: 120, height: 18),
                CGRect(x: 324, y: 342, width: 108, height: 18)
            ]
        )
        let comment = try comment(text: "This claim leans hard on an underspecified baseline.")

        let layout = ReaderElfOverlayLayout.resolve(
            for: overlayState(status: .coolingDown(until: .now), comment: comment, geometry: geometry)
        )

        XCTAssertEqual(layout.bubblePlacement, .above)
        XCTAssertLessThan(try XCTUnwrap(layout.bubbleFrame).maxY, try XCTUnwrap(geometry.anchorFrame).minY)
    }

    func testOverlayLayoutFallsBackToBelowWhenTopEdgeIsConstrained() throws {
        let geometry = geometry(
            paneBounds: CGRect(x: 0, y: 0, width: 920, height: 720),
            pageFrame: CGRect(x: 240, y: 48, width: 560, height: 610),
            anchorFrame: CGRect(x: 420, y: 72, width: 120, height: 40),
            passageLineFrames: [
                CGRect(x: 420, y: 72, width: 120, height: 18),
                CGRect(x: 420, y: 96, width: 114, height: 18)
            ]
        )
        let comment = try comment(text: "The empirical story ignores the compute budget entirely.")

        let layout = ReaderElfOverlayLayout.resolve(
            for: overlayState(status: .coolingDown(until: .now), comment: comment, geometry: geometry)
        )

        XCTAssertEqual(layout.bubblePlacement, .below)
        XCTAssertGreaterThan(try XCTUnwrap(layout.bubbleFrame).minY, try XCTUnwrap(geometry.anchorFrame).maxY)
    }

    func testOverlayLayoutUsesSideFallbackWhenVerticalPlacementsAreConstrained() throws {
        let geometry = geometry(
            paneBounds: CGRect(x: 0, y: 0, width: 760, height: 420),
            pageFrame: CGRect(x: 120, y: 48, width: 420, height: 212),
            anchorFrame: CGRect(x: 172, y: 112, width: 96, height: 34),
            passageLineFrames: [
                CGRect(x: 172, y: 112, width: 96, height: 16),
                CGRect(x: 172, y: 132, width: 104, height: 16)
            ]
        )
        let comment = try comment(text: "The paragraph leaps from anecdote to mechanism without showing the bridge.")

        let layout = ReaderElfOverlayLayout.resolve(
            for: overlayState(status: .coolingDown(until: .now), comment: comment, geometry: geometry)
        )

        XCTAssertEqual(layout.bubblePlacement, .trailing)
        XCTAssertGreaterThan(try XCTUnwrap(layout.bubbleFrame).minX, try XCTUnwrap(geometry.anchorFrame).maxX)
    }

    func testOverlayLayoutClampsBubbleWithinVisiblePageBoundsWhenNoPlacementFullyFits() throws {
        let geometry = geometry(
            paneBounds: CGRect(x: 0, y: 0, width: 520, height: 360),
            pageFrame: CGRect(x: 116, y: 56, width: 196, height: 132),
            anchorFrame: CGRect(x: 154, y: 84, width: 72, height: 26),
            passageLineFrames: [
                CGRect(x: 154, y: 84, width: 72, height: 14),
                CGRect(x: 156, y: 104, width: 68, height: 14)
            ]
        )
        let comment = try comment(text: "A long critique that still should not cover the paper when the margins are cramped.")

        let layout = ReaderElfOverlayLayout.resolve(
            for: overlayState(status: .coolingDown(until: .now), comment: comment, geometry: geometry)
        )

        XCTAssertEqual(layout.bubblePlacement, .above)
        XCTAssertNotNil(layout.bubbleFrame)
        XCTAssertTrue(try XCTUnwrap(geometry.pageFrame).contains(try XCTUnwrap(layout.bubbleFrame)))
    }

    func testOverlayLayoutKeepsFigureDockedWhenElfIsOff() {
        let geometry = geometry(
            paneBounds: CGRect(x: 0, y: 0, width: 820, height: 620),
            pageFrame: nil,
            anchorFrame: nil
        )

        let layout = ReaderElfOverlayLayout.resolve(
            for: overlayState(status: .off, comment: nil, geometry: geometry)
        )

        XCTAssertNil(layout.bubbleFrame)
        XCTAssertEqual(layout.figureFrame.minX, 744, accuracy: 0.001)
        XCTAssertEqual(layout.figureFrame.minY, 516, accuracy: 0.001)
    }

    func testOverlayLayoutReturnsToDockAfterCommentDismissal() throws {
        let geometry = geometry(
            paneBounds: CGRect(x: 0, y: 0, width: 900, height: 700),
            pageFrame: CGRect(x: 190, y: 52, width: 470, height: 580),
            anchorFrame: CGRect(x: 342, y: 300, width: 140, height: 44),
            passageLineFrames: [
                CGRect(x: 342, y: 300, width: 140, height: 20),
                CGRect(x: 346, y: 326, width: 132, height: 20)
            ]
        )
        let comment = try comment(text: "This ablation matrix is too thin for the strength of the claim.")

        let activeLayout = ReaderElfOverlayLayout.resolve(
            for: overlayState(status: .coolingDown(until: .now), comment: comment, geometry: geometry)
        )
        let idleLayout = ReaderElfOverlayLayout.resolve(
            for: overlayState(status: .listening, comment: nil, geometry: geometry)
        )

        XCTAssertNotEqual(activeLayout.figureFrame, idleLayout.figureFrame)
        XCTAssertNil(idleLayout.bubbleFrame)
        XCTAssertEqual(idleLayout.figureFrame.maxX, geometry.paneBounds.maxX - 18, accuracy: 0.001)
        XCTAssertEqual(idleLayout.figureFrame.maxY, geometry.paneBounds.maxY - 18, accuracy: 0.001)
    }

    func testOverlayLayoutUsesClippedPresentationAnchorWhenPassageIsPartiallyVisible() throws {
        let partiallyVisibleGeometry = geometry(
            paneBounds: CGRect(x: 0, y: 0, width: 900, height: 720),
            pageFrame: CGRect(x: 180, y: -44, width: 500, height: 760),
            anchorFrame: CGRect(x: 332, y: -18, width: 126, height: 58),
            passageLineFrames: [
                CGRect(x: 332, y: -18, width: 126, height: 18),
                CGRect(x: 336, y: 6, width: 118, height: 18)
            ]
        )
        let comment = try comment(text: "This passage should still attract the elf when the paragraph is only partly on screen.")

        let matchedGeometry = geometry(
            passageKey: comment.passage.normalizedKey,
            paneBounds: partiallyVisibleGeometry.paneBounds,
            pageFrame: partiallyVisibleGeometry.pageFrame,
            anchorFrame: partiallyVisibleGeometry.anchorFrame,
            passageLineFrames: partiallyVisibleGeometry.passageLineFrames
        )
        let state = overlayState(
            status: .coolingDown(until: .now),
            comment: comment,
            geometry: matchedGeometry
        )
        let layout = ReaderElfOverlayLayout.resolve(for: state)

        XCTAssertNotNil(matchedGeometry.presentationAnchorFrame)
        XCTAssertNotEqual(layout.figureFrame, layout.dockFrame)
        XCTAssertNotNil(layout.bubbleFrame)
    }

    func testOverlayLayoutMovesElfOffscreenInsteadOfDockingWhenTargetParagraphIsOffscreen() throws {
        let comment = try comment(text: "This paragraph still overclaims what the evidence establishes.")
        let geometry = geometry(
            passageKey: comment.passage.normalizedKey,
            paneBounds: CGRect(x: 0, y: 0, width: 920, height: 720),
            pageFrame: CGRect(x: 160, y: -680, width: 520, height: 620),
            anchorFrame: CGRect(x: 310, y: -232, width: 150, height: 42),
            passageLineFrames: [CGRect(x: 310, y: -232, width: 150, height: 18)]
        )
        let state = overlayState(
            status: .coolingDown(until: .now),
            comment: comment,
            geometry: geometry
        )
        let layout = ReaderElfOverlayLayout.resolve(for: state)

        XCTAssertNotEqual(layout.figureFrame, layout.dockFrame)
        XCTAssertNil(layout.bubbleFrame)
        XCTAssertLessThan(layout.figureFrame.maxY, geometry.paneBounds.minY)
    }

    func testPresentationStateProgressesThroughPhasesAndClearsAtDock() throws {
        var presentation = ReaderElfPresentationState()
        let comment = try comment(text: "This control is too weak for the claim.")
        let targetGeometry = geometry(
            paneBounds: CGRect(x: 0, y: 0, width: 920, height: 720),
            pageFrame: CGRect(x: 180, y: 48, width: 480, height: 600),
            anchorFrame: CGRect(x: 332, y: 286, width: 126, height: 42),
            passageLineFrames: [
                CGRect(x: 332, y: 286, width: 126, height: 18),
                CGRect(x: 336, y: 310, width: 118, height: 18)
            ]
        )

        presentation.start(comment: comment, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(presentation.phase, .docked)
        XCTAssertEqual(presentation.targetResolution, .awaitingGeometry(expectedPassageKey: comment.passage.normalizedKey))
        XCTAssertEqual(presentation.token, comment.id)

        presentation.resolveGeometry(
            geometry(
                passageKey: comment.passage.normalizedKey,
                paneBounds: targetGeometry.paneBounds,
                pageFrame: targetGeometry.pageFrame,
                anchorFrame: targetGeometry.anchorFrame,
                passageLineFrames: targetGeometry.passageLineFrames
            ),
            commentID: comment.id,
            at: Date(timeIntervalSince1970: 10.5)
        )
        XCTAssertEqual(presentation.phase, .jumpingIn)
        XCTAssertEqual(presentation.targetResolution, .ready)

        presentation.beginPresenting(commentID: comment.id, at: Date(timeIntervalSince1970: 11))
        XCTAssertEqual(presentation.phase, .presenting)

        presentation.beginReturning(commentID: comment.id, at: Date(timeIntervalSince1970: 12))
        XCTAssertEqual(presentation.phase, .returning)

        presentation.dock(commentID: comment.id, at: Date(timeIntervalSince1970: 13))
        XCTAssertEqual(presentation.phase, .docked)
        XCTAssertNil(presentation.comment)
        XCTAssertNil(presentation.geometry)
        XCTAssertNil(presentation.token)
    }

    func testOverlayStatePrefersLiveMatchedGeometryOverLandingGeometryWhilePresenting() throws {
        let landingGeometry = geometry(
            paneBounds: CGRect(x: 0, y: 0, width: 840, height: 680),
            pageFrame: CGRect(x: 170, y: 44, width: 420, height: 560),
            anchorFrame: CGRect(x: 318, y: 280, width: 118, height: 40),
            passageLineFrames: [
                CGRect(x: 318, y: 280, width: 118, height: 18),
                CGRect(x: 322, y: 304, width: 110, height: 18)
            ]
        )
        let liveGeometry = geometry(
            paneBounds: CGRect(x: 0, y: 0, width: 840, height: 680),
            pageFrame: CGRect(x: 120, y: 32, width: 520, height: 600),
            anchorFrame: CGRect(x: 200, y: 92, width: 160, height: 48),
            passageLineFrames: [CGRect(x: 200, y: 92, width: 160, height: 18)]
        )
        let comment = try comment(text: "The baseline control is still underspecified.")
        let presentation = ReaderElfPresentationState(
            comment: comment,
            geometry: landingGeometry,
            liveGeometry: liveGeometry,
            phase: .presenting,
            targetResolution: .ready,
            phaseStartedAt: Date(timeIntervalSince1970: 30),
            token: comment.id
        )

        let state = ReaderElfOverlayState(
            status: .coolingDown(until: .now),
            presentation: presentation,
            geometry: liveGeometry
        )

        XCTAssertEqual(state.anchorFrame, liveGeometry.anchorFrame)
        XCTAssertEqual(state.passageLineFrames, liveGeometry.passageLineFrames)
    }

    func testOverlayStateFallsBackToLandingGeometryDuringReturnWhenLiveGeometryIsUnavailable() throws {
        let landingGeometry = geometry(
            paneBounds: CGRect(x: 0, y: 0, width: 840, height: 680),
            pageFrame: CGRect(x: 170, y: 44, width: 420, height: 560),
            anchorFrame: CGRect(x: 318, y: 280, width: 118, height: 40),
            passageLineFrames: [
                CGRect(x: 318, y: 280, width: 118, height: 18),
                CGRect(x: 322, y: 304, width: 110, height: 18)
            ]
        )
        let liveGeometry = geometry(
            paneBounds: CGRect(x: 0, y: 0, width: 840, height: 680),
            pageFrame: CGRect(x: 120, y: 32, width: 520, height: 600),
            anchorFrame: CGRect(x: 200, y: 92, width: 160, height: 48),
            passageLineFrames: [CGRect(x: 200, y: 92, width: 160, height: 18)]
        )
        let comment = try comment(text: "The baseline control is still underspecified.")
        let presentation = ReaderElfPresentationState(
            comment: comment,
            geometry: landingGeometry,
            liveGeometry: liveGeometry,
            phase: .returning,
            targetResolution: .ready,
            phaseStartedAt: Date(timeIntervalSince1970: 30),
            token: comment.id
        )

        let state = ReaderElfOverlayState(
            status: .coolingDown(until: .now),
            presentation: presentation,
            geometry: nil
        )

        XCTAssertEqual(state.anchorFrame, liveGeometry.anchorFrame)
        XCTAssertEqual(state.passageLineFrames, liveGeometry.passageLineFrames)

        let fallbackState = ReaderElfOverlayState(
            status: .coolingDown(until: .now),
            presentation: ReaderElfPresentationState(
                comment: comment,
                geometry: landingGeometry,
                liveGeometry: nil,
                phase: .returning,
                targetResolution: .ready,
                phaseStartedAt: Date(timeIntervalSince1970: 30),
                token: comment.id
            ),
            geometry: nil
        )

        XCTAssertEqual(fallbackState.anchorFrame, landingGeometry.anchorFrame)
        XCTAssertEqual(fallbackState.passageLineFrames, landingGeometry.passageLineFrames)
    }

    func testUnderlinePresentationUsesCommentPassageRectsInsteadOfLiveGeometry() throws {
        let rects = [
            ReaderAnnotationRect(rect: CGRect(x: 24, y: 160, width: 132, height: 16)),
            ReaderAnnotationRect(rect: CGRect(x: 24, y: 138, width: 126, height: 16))
        ]
        let comment = try comment(
            text: "This chain of reasoning still skips the ablation that matters.",
            pageIndex: 3,
            rects: rects
        )
        let presentation = ReaderElfPresentationState(
            comment: comment,
            geometry: geometry(
                passageKey: comment.passage.normalizedKey,
                paneBounds: CGRect(x: 0, y: 0, width: 900, height: 720),
                pageFrame: CGRect(x: 180, y: 44, width: 500, height: 620),
                anchorFrame: CGRect(x: 310, y: 280, width: 160, height: 54),
                passageLineFrames: [
                    CGRect(x: 310, y: 280, width: 160, height: 18),
                    CGRect(x: 314, y: 304, width: 152, height: 18),
                    CGRect(x: 312, y: 328, width: 146, height: 18)
                ]
            ),
            phase: .presenting,
            targetResolution: .ready,
            phaseStartedAt: Date(timeIntervalSince1970: 100),
            token: comment.id
        )

        let underline = try XCTUnwrap(ReaderElfUnderlinePresentationState(presentation))

        XCTAssertEqual(underline.commentID, comment.id)
        XCTAssertEqual(underline.pageIndex, comment.passage.pageIndex)
        XCTAssertEqual(underline.rects, rects)
    }

    func testUnderlineTimelineCreatesOneUnderlinePerPassageRect() {
        let rects = [
            ReaderAnnotationRect(rect: CGRect(x: 48, y: 212, width: 160, height: 18)),
            ReaderAnnotationRect(rect: CGRect(x: 52, y: 188, width: 152, height: 18)),
            ReaderAnnotationRect(rect: CGRect(x: 50, y: 164, width: 146, height: 18))
        ]
        let startedAt = Date(timeIntervalSince1970: 100)
        let presentation = ReaderElfUnderlinePresentationState(
            commentID: UUID(),
            pageIndex: 0,
            rects: rects,
            phase: .presenting,
            phaseStartedAt: startedAt,
            mood: .skeptical
        )
        let snapshot = ReaderElfUnderlineTimeline.snapshot(
            for: presentation,
            at: startedAt.addingTimeInterval(0.9)
        )

        XCTAssertEqual(snapshot.segments.count, rects.count)
        for (segment, lineFrame) in zip(snapshot.segments, ReaderElfUnderlineTimeline.underlineFrames(from: rects)) {
            XCTAssertEqual(segment.progress, 1, accuracy: 0.001)
            XCTAssertLessThanOrEqual(segment.frame.maxX, lineFrame.maxX + 0.001)
            XCTAssertEqual(segment.frame.minX, lineFrame.minX, accuracy: 0.001)
        }
    }

    func testUnderlineFramesSitJustBelowTheirSourceLines() {
        let lineFrames = [
            ReaderAnnotationRect(rect: CGRect(x: 240, y: 200, width: 160, height: 18)),
            ReaderAnnotationRect(rect: CGRect(x: 244, y: 224, width: 152, height: 18))
        ]

        let underlineFrames = ReaderElfUnderlineTimeline.underlineFrames(from: lineFrames)

        XCTAssertEqual(underlineFrames.count, lineFrames.count)
        XCTAssertEqual(underlineFrames[0].minY, lineFrames[0].cgRect.minY - 1, accuracy: 0.001)
        XCTAssertEqual(underlineFrames[1].minY, lineFrames[1].cgRect.minY - 1, accuracy: 0.001)
    }

    func testUnderlineTimelineFadesDuringReturnAndClearsItWhenDocked() {
        let rects = [
            ReaderAnnotationRect(rect: CGRect(x: 48, y: 212, width: 150, height: 18)),
            ReaderAnnotationRect(rect: CGRect(x: 52, y: 188, width: 142, height: 18))
        ]
        let returningAt = Date(timeIntervalSince1970: 200)
        let returningState = ReaderElfUnderlinePresentationState(
            commentID: UUID(),
            pageIndex: 0,
            rects: rects,
            phase: .returning,
            phaseStartedAt: returningAt,
            mood: .skeptical
        )
        let returningSnapshot = ReaderElfUnderlineTimeline.snapshot(
            for: returningState,
            at: returningAt.addingTimeInterval(0.14)
        )

        XCTAssertGreaterThan(returningSnapshot.opacity, 0)
        XCTAssertLessThan(returningSnapshot.opacity, 1)
        XCTAssertEqual(returningSnapshot.segments.count, rects.count)

        let dockedSnapshot = ReaderElfUnderlineTimeline.snapshot(
            for: nil,
            at: returningAt.addingTimeInterval(1)
        )

        XCTAssertEqual(dockedSnapshot.opacity, 0, accuracy: 0.001)
        XCTAssertTrue(dockedSnapshot.segments.isEmpty)
    }

    func testPresentationWaitsForMatchingGeometryBeforeShowingComment() throws {
        var presentation = ReaderElfPresentationState()
        let comment = try comment(text: "This conclusion is too broad for the presented evidence.")
        let mismatchedGeometry = geometry(
            passageKey: "other-passage",
            paneBounds: CGRect(x: 0, y: 0, width: 900, height: 720),
            pageFrame: CGRect(x: 180, y: 44, width: 500, height: 620),
            anchorFrame: CGRect(x: 300, y: 280, width: 140, height: 42),
            passageLineFrames: [CGRect(x: 300, y: 280, width: 140, height: 18)]
        )
        let matchedGeometry = geometry(
            passageKey: comment.passage.normalizedKey,
            paneBounds: CGRect(x: 0, y: 0, width: 900, height: 720),
            pageFrame: CGRect(x: 180, y: 44, width: 500, height: 620),
            anchorFrame: CGRect(x: 310, y: 286, width: 150, height: 42),
            passageLineFrames: [CGRect(x: 310, y: 286, width: 150, height: 18)]
        )

        presentation.start(comment: comment, at: Date(timeIntervalSince1970: 10))
        presentation.resolveGeometry(mismatchedGeometry, commentID: comment.id, at: Date(timeIntervalSince1970: 11))

        XCTAssertEqual(presentation.targetResolution, .awaitingGeometry(expectedPassageKey: comment.passage.normalizedKey))
        XCTAssertEqual(presentation.phase, .docked)
        XCTAssertNil(presentation.displayedComment)

        presentation.resolveGeometry(matchedGeometry, commentID: comment.id, at: Date(timeIntervalSince1970: 12))

        XCTAssertEqual(presentation.targetResolution, .ready)
        XCTAssertEqual(presentation.phase, .jumpingIn)
        XCTAssertEqual(presentation.geometry?.passageKey, comment.passage.normalizedKey)
    }

    func testPresentationGeometryUpdateWaitsForMatchedGeometry() throws {
        let comment = try comment(text: "This section still jumps past the control that matters.")
        let mismatchedGeometry = geometry(
            passageKey: "other-passage",
            paneBounds: CGRect(x: 0, y: 0, width: 920, height: 720),
            pageFrame: CGRect(x: 160, y: 48, width: 520, height: 620),
            anchorFrame: CGRect(x: 312, y: 286, width: 160, height: 42),
            passageLineFrames: [CGRect(x: 312, y: 286, width: 160, height: 18)]
        )
        let matchedGeometry = geometry(
            passageKey: comment.passage.normalizedKey,
            paneBounds: CGRect(x: 0, y: 0, width: 920, height: 720),
            pageFrame: CGRect(x: 160, y: 48, width: 520, height: 620),
            anchorFrame: CGRect(x: 312, y: 286, width: 160, height: 42),
            passageLineFrames: [CGRect(x: 312, y: 286, width: 160, height: 18)]
        )
        var presentation = ReaderElfPresentationState()

        presentation.start(comment: comment, at: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(presentation.geometryUpdate(for: mismatchedGeometry), .none)
        XCTAssertEqual(presentation.geometryUpdate(for: matchedGeometry), .resolve(matchedGeometry))
    }

    func testPresentationGeometryUpdateAllowsOffscreenMatchedGeometry() throws {
        let comment = try comment(text: "This section still jumps past the control that matters.")
        let offscreenMatchedGeometry = geometry(
            passageKey: comment.passage.normalizedKey,
            paneBounds: CGRect(x: 0, y: 0, width: 920, height: 720),
            pageFrame: CGRect(x: 160, y: 780, width: 520, height: 620),
            anchorFrame: CGRect(x: 312, y: 812, width: 160, height: 42),
            passageLineFrames: [CGRect(x: 312, y: 812, width: 160, height: 18)]
        )
        var presentation = ReaderElfPresentationState()

        presentation.start(comment: comment, at: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(presentation.geometryUpdate(for: offscreenMatchedGeometry), .resolve(offscreenMatchedGeometry))
    }

    func testPresentationGeometryUpdateRequestsReturnWhenReadyPresentationLosesTargetMatch() throws {
        let comment = try comment(text: "The justification still does not reach the stated claim.")
        let readyGeometry = geometry(
            passageKey: comment.passage.normalizedKey,
            paneBounds: CGRect(x: 0, y: 0, width: 920, height: 720),
            pageFrame: CGRect(x: 160, y: 48, width: 520, height: 620),
            anchorFrame: CGRect(x: 312, y: 286, width: 160, height: 42),
            passageLineFrames: [CGRect(x: 312, y: 286, width: 160, height: 18)]
        )
        var presentation = ReaderElfPresentationState()

        presentation.start(comment: comment, at: Date(timeIntervalSince1970: 30))
        presentation.resolveGeometry(readyGeometry, commentID: comment.id, at: Date(timeIntervalSince1970: 31))
        presentation.beginPresenting(commentID: comment.id, at: Date(timeIntervalSince1970: 32))

        XCTAssertEqual(presentation.geometryUpdate(for: nil), .returnToDock)
        XCTAssertEqual(
            presentation.geometryUpdate(
                for: geometry(
                    passageKey: "other-passage",
                    paneBounds: readyGeometry.paneBounds,
                    pageFrame: readyGeometry.pageFrame,
                    anchorFrame: readyGeometry.anchorFrame,
                    passageLineFrames: readyGeometry.passageLineFrames
                )
            ),
            .returnToDock
        )
        XCTAssertEqual(presentation.geometryUpdate(for: readyGeometry), .refresh(readyGeometry))
    }

    func testGeometryReadinessSucceedsForPartiallyVisibleMatchedPassage() throws {
        let geometry = geometry(
            passageKey: "target",
            paneBounds: CGRect(x: 0, y: 0, width: 920, height: 720),
            pageFrame: CGRect(x: 160, y: -52, width: 520, height: 760),
            anchorFrame: CGRect(x: 312, y: -18, width: 160, height: 74),
            passageLineFrames: [
                CGRect(x: 312, y: -18, width: 160, height: 18),
                CGRect(x: 316, y: 6, width: 152, height: 18),
                CGRect(x: 314, y: 30, width: 148, height: 18)
            ]
        )

        XCTAssertTrue(geometry.isReadyForPresentation(expectedPassageKey: "target"))
        assertRectEqual(
            try XCTUnwrap(geometry.presentationAnchorFrame),
            CGRect(x: 312, y: 0, width: 160, height: 56)
        )
    }

    func testGeometryReadinessRejectsMismatchedPassageKey() {
        let geometry = geometry(
            passageKey: "other",
            paneBounds: CGRect(x: 0, y: 0, width: 920, height: 720),
            pageFrame: CGRect(x: 160, y: 48, width: 520, height: 620),
            anchorFrame: CGRect(x: 312, y: 286, width: 160, height: 42),
            passageLineFrames: [CGRect(x: 312, y: 286, width: 160, height: 18)]
        )

        XCTAssertFalse(geometry.isReadyForPresentation(expectedPassageKey: "target"))
    }

    func testPresentationTargetMatchingSucceedsEvenWhenParagraphIsOffscreen() {
        let geometry = geometry(
            passageKey: "target",
            paneBounds: CGRect(x: 0, y: 0, width: 920, height: 720),
            pageFrame: CGRect(x: 160, y: 780, width: 520, height: 620),
            anchorFrame: CGRect(x: 312, y: 812, width: 160, height: 42),
            passageLineFrames: [CGRect(x: 312, y: 812, width: 160, height: 18)]
        )

        XCTAssertTrue(geometry.matchesPresentationTarget(expectedPassageKey: "target"))
        XCTAssertFalse(geometry.isReadyForPresentation(expectedPassageKey: "target"))
    }

    func testUnderlinePresentationRemainsNilUntilGeometryIsReady() throws {
        var presentation = ReaderElfPresentationState()
        let comment = try comment(text: "This metric swap still lacks justification.")
        let matchedGeometry = geometry(
            passageKey: comment.passage.normalizedKey,
            paneBounds: CGRect(x: 0, y: 0, width: 860, height: 680),
            pageFrame: CGRect(x: 150, y: 40, width: 480, height: 580),
            anchorFrame: CGRect(x: 260, y: 156, width: 168, height: 38),
            passageLineFrames: [CGRect(x: 260, y: 156, width: 168, height: 18)]
        )

        presentation.start(comment: comment, at: Date(timeIntervalSince1970: 20))
        XCTAssertNil(ReaderElfUnderlinePresentationState(presentation))

        presentation.resolveGeometry(matchedGeometry, commentID: comment.id, at: Date(timeIntervalSince1970: 21))

        let underline = try XCTUnwrap(ReaderElfUnderlinePresentationState(presentation))
        XCTAssertEqual(underline.commentID, comment.id)
        XCTAssertEqual(underline.rects, comment.passage.rects)
    }

    func testGeometryResolutionTimeoutGivesRealPDFJumpsMoreTimeToSettle() {
        XCTAssertEqual(ReaderElfPresentationState.geometryResolutionTimeout, 0.75, accuracy: 0.001)
        XCTAssertEqual(ReaderElfPresentationState.geometryResolutionMaximumWait, 3.0, accuracy: 0.001)
    }

    func testGeometryResolutionWaitIntervalUsesIdleTimeoutWithoutViewportMovement() {
        let startedAt = Date(timeIntervalSince1970: 50)
        let now = Date(timeIntervalSince1970: 50.2)

        let waitInterval = ReaderElfPresentationState.geometryResolutionWaitInterval(
            startedAt: startedAt,
            lastViewportActivityAt: nil,
            now: now
        )

        XCTAssertEqual(try XCTUnwrap(waitInterval), 0.55, accuracy: 0.001)
    }

    func testGeometryResolutionWaitIntervalExtendsAfterRecentViewportMovement() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let lastViewportActivityAt = Date(timeIntervalSince1970: 100.65)
        let now = Date(timeIntervalSince1970: 100.7)

        let waitInterval = ReaderElfPresentationState.geometryResolutionWaitInterval(
            startedAt: startedAt,
            lastViewportActivityAt: lastViewportActivityAt,
            now: now
        )

        XCTAssertEqual(try XCTUnwrap(waitInterval), 0.7, accuracy: 0.001)
    }

    func testGeometryResolutionWaitIntervalStopsAtMaximumWaitEvenWithViewportMovement() {
        let startedAt = Date(timeIntervalSince1970: 200)
        let lastViewportActivityAt = Date(timeIntervalSince1970: 202.9)
        let now = Date(timeIntervalSince1970: 202.95)

        let waitInterval = ReaderElfPresentationState.geometryResolutionWaitInterval(
            startedAt: startedAt,
            lastViewportActivityAt: lastViewportActivityAt,
            now: now
        )

        XCTAssertEqual(try XCTUnwrap(waitInterval), 0.05, accuracy: 0.001)
    }

    func testGeometryResolutionWaitIntervalExpiresAfterMaximumWait() {
        let startedAt = Date(timeIntervalSince1970: 300)
        let now = Date(timeIntervalSince1970: 303.01)

        XCTAssertNil(
            ReaderElfPresentationState.geometryResolutionWaitInterval(
                startedAt: startedAt,
                lastViewportActivityAt: Date(timeIntervalSince1970: 302.8),
                now: now
            )
        )
    }

    func testBubbleStyleUsesTintedReadableTextDistinctFromPDFBlack() {
        let style = ReaderElfBubbleStyle.make(for: .skeptical)

        XCTAssertFalse(colorsMatch(style.textColor, ReaderElfBubbleStyle.pdfBodyReferenceColor))
    }

    func testBubbleStyleKeepsMainTextColorStableAcrossMoods() {
        let skepticalStyle = ReaderElfBubbleStyle.make(for: .skeptical)
        let alarmedStyle = ReaderElfBubbleStyle.make(for: .alarmed)

        XCTAssertTrue(colorsMatch(skepticalStyle.textColor, alarmedStyle.textColor))
        XCTAssertFalse(colorsMatch(skepticalStyle.accentColor, alarmedStyle.accentColor))
    }

    private func passage(
        pageIndex: Int,
        text: String,
        rects: [ReaderAnnotationRect] = [ReaderAnnotationRect(rect: CGRect(x: 12, y: 20, width: 88, height: 14))]
    ) throws -> ReaderFocusPassageSnapshot {
        try XCTUnwrap(
            ReaderFocusPassageSnapshot(
                pageIndex: pageIndex,
                quotedText: text,
                rects: rects,
                source: .viewport
            )
        )
    }

    private func line(text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> ReaderPassageLine {
        ReaderPassageLine(
            text: text,
            rect: ReaderAnnotationRect(rect: CGRect(x: x, y: y, width: width, height: height))
        )
    }

    private func comment(
        text: String,
        pageIndex: Int = 0,
        rects: [ReaderAnnotationRect] = [ReaderAnnotationRect(rect: CGRect(x: 12, y: 20, width: 88, height: 14))]
    ) throws -> ReaderElfComment {
        ReaderElfComment(
            passage: try passage(pageIndex: pageIndex, text: "A focused paragraph", rects: rects),
            mood: .skeptical,
            text: text
        )
    }

    private func geometry(
        passageKey: String? = nil,
        paneBounds: CGRect,
        pageFrame: CGRect?,
        anchorFrame: CGRect?,
        presentationAnchorFrame: CGRect? = nil,
        passageLineFrames: [CGRect] = []
    ) -> ReaderElfGeometrySnapshot {
        ReaderElfGeometrySnapshot(
            passageKey: passageKey,
            paneBounds: paneBounds,
            pageFrame: pageFrame,
            anchorFrame: anchorFrame,
            presentationAnchorFrame: presentationAnchorFrame,
            passageLineFrames: passageLineFrames
        )
    }

    private func overlayState(
        status: ReaderElfStatus,
        comment: ReaderElfComment?,
        geometry: ReaderElfGeometrySnapshot,
        phase: ReaderElfPresentationPhase? = nil,
        startedAt: Date = .distantPast
    ) -> ReaderElfOverlayState {
        let resolvedPhase = phase ?? (comment == nil ? .docked : .presenting)
        let presentation = ReaderElfPresentationState(
            comment: comment,
            geometry: comment == nil ? nil : geometry,
            phase: resolvedPhase,
            targetResolution: comment == nil ? .idle : .ready,
            phaseStartedAt: startedAt,
            token: comment?.id
        )

        return ReaderElfOverlayState(
            status: status,
            presentation: presentation,
            geometry: geometry
        )
    }

    private func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        let left = lhs.usingColorSpace(.deviceRGB) ?? lhs
        let right = rhs.usingColorSpace(.deviceRGB) ?? rhs
        return abs(left.redComponent - right.redComponent) < 0.001
            && abs(left.greenComponent - right.greenComponent) < 0.001
            && abs(left.blueComponent - right.blueComponent) < 0.001
            && abs(left.alphaComponent - right.alphaComponent) < 0.001
    }

    private func assertRectEqual(_ lhs: CGRect, _ rhs: CGRect, accuracy: CGFloat = 0.001) {
        XCTAssertEqual(lhs.minX, rhs.minX, accuracy: accuracy)
        XCTAssertEqual(lhs.minY, rhs.minY, accuracy: accuracy)
        XCTAssertEqual(lhs.width, rhs.width, accuracy: accuracy)
        XCTAssertEqual(lhs.height, rhs.height, accuracy: accuracy)
    }
}
