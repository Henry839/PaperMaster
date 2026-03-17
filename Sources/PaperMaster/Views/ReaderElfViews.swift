import SwiftUI

struct ReaderElfPaneOverlayView: View {
    let state: ReaderElfOverlayState
    let onTapActiveElf: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                let resolvedState = stateWithPaneBounds(CGRect(origin: .zero, size: proxy.size))
                let layout = ReaderElfOverlayLayout.resolve(for: resolvedState)
                let motion = ReaderElfPresentationTimeline.snapshot(
                    for: resolvedState,
                    layout: layout,
                    at: context.date
                )
                let timestamp = context.date.timeIntervalSinceReferenceDate
                let bob = CGFloat(sin(timestamp * 2.8)) * motion.bobAmplitude
                let blinkValue = abs(sin(timestamp * 1.55))
                let blinkScale: CGFloat = blinkValue > 0.985 ? 0.18 : 1.0

                ZStack(alignment: .topLeading) {
                    Group {
                        if let comment = resolvedState.presentedComment,
                           let bubbleFrame = layout.bubbleFrame,
                           let bubblePlacement = layout.bubblePlacement,
                           motion.bubbleOpacity > 0.01 {
                            ReaderElfBubble(
                                comment: comment,
                                placement: bubblePlacement,
                                tailTip: layout.tailTip.map { tip in
                                    CGPoint(x: tip.x - bubbleFrame.minX, y: tip.y - bubbleFrame.minY)
                                }
                            )
                                .frame(width: bubbleFrame.width, height: bubbleFrame.height, alignment: .topLeading)
                                .scaleEffect(motion.bubbleScale, anchor: bubbleAnchor(for: bubblePlacement))
                                .opacity(motion.bubbleOpacity)
                                .offset(x: bubbleFrame.minX, y: bubbleFrame.minY)
                        }

                        ReaderElfFigure(
                            mood: figureMood(for: resolvedState),
                            blinkScale: blinkScale,
                            parked: resolvedState.status == .off
                        )
                        .frame(width: motion.figureFrame.width, height: motion.figureFrame.height)
                        .opacity(figureOpacity(for: resolvedState))
                        .offset(x: motion.figureFrame.minX, y: motion.figureFrame.minY + bob)
                    }
                    .allowsHitTesting(false)

                    if let onTapActiveElf,
                       resolvedState.presentedComment != nil,
                       resolvedState.presentationPhase != .returning {
                        Color.clear
                            .frame(
                                width: motion.figureFrame.width,
                                height: motion.figureFrame.height,
                                alignment: .topLeading
                            )
                            .contentShape(Rectangle())
                            .offset(x: motion.figureFrame.minX, y: motion.figureFrame.minY + bob)
                            .onTapGesture(perform: onTapActiveElf)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(Color.clear)
    }

    private func stateWithPaneBounds(_ paneBounds: CGRect) -> ReaderElfOverlayState {
        let geometry = ReaderElfGeometrySnapshot(
            passageKey: state.passageKey,
            paneBounds: paneBounds,
            pageFrame: state.pageFrame,
            anchorFrame: state.anchorFrame,
            presentationAnchorFrame: state.presentationAnchorFrame,
            passageLineFrames: state.passageLineFrames
        )
        return ReaderElfOverlayState(
            status: state.status,
            presentation: ReaderElfPresentationState(
                comment: state.presentedComment,
                geometry: geometry,
                phase: state.presentationPhase,
                targetResolution: state.targetResolution,
                phaseStartedAt: state.presentationStartedAt,
                token: state.presentationToken
            ),
            dockCorner: state.dockCorner,
            geometry: geometry,
            preferredBubblePlacement: state.preferredBubblePlacement
        )
    }

    private func figureMood(for state: ReaderElfOverlayState) -> ReaderElfMood {
        if let activeComment = state.presentedComment {
            return activeComment.mood
        }
        switch state.status {
        case .off:
            return .skeptical
        case .paused:
            return .alarmed
        case .thinking:
            return .intrigued
        case .coolingDown:
            return .amused
        case .listening:
            return .intrigued
        }
    }

    private func figureOpacity(for state: ReaderElfOverlayState) -> Double {
        if state.presentedComment != nil {
            return 0.98
        }

        switch state.status {
        case .off:
            return 0.5
        case .paused:
            return 0.82
        case .thinking:
            return 0.96
        case .coolingDown, .listening:
            return 0.9
        }
    }

    private func bubbleAnchor(for placement: ReaderElfBubblePlacement) -> UnitPoint {
        switch placement {
        case .above:
            return .bottom
        case .below:
            return .top
        case .leading:
            return .trailing
        case .trailing:
            return .leading
        }
    }
}

private struct ReaderElfBubble: View {
    let comment: ReaderElfComment
    let placement: ReaderElfBubblePlacement
    let tailTip: CGPoint?

    var body: some View {
        let style = ReaderElfBubbleStyle.make(for: comment.mood)
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(comment.mood.displayName, systemImage: comment.mood.symbolName)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(nsColor: style.accentColor))

                Spacer(minLength: 0)

                Text("Page \(comment.passage.pageNumber)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(nsColor: style.secondaryTextColor))
            }

            Text(comment.text)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color(nsColor: style.textColor))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: style.fillTopColor),
                            Color(nsColor: style.fillBottomColor)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            GeometryReader { proxy in
                if let tailTip {
                    ReaderElfBubbleTail(placement: placement)
                        .fill(Color(nsColor: style.tailColor))
                        .frame(width: 18, height: 14)
                        .overlay {
                            ReaderElfBubbleTail(placement: placement)
                                .stroke(Color(nsColor: style.borderColor), lineWidth: 1)
                        }
                        .position(tailPosition(in: proxy.size, tailTip: tailTip))
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: style.borderColor), lineWidth: 1.05)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 12, y: 7)
    }

    private func tailPosition(in size: CGSize, tailTip: CGPoint) -> CGPoint {
        switch placement {
        case .above:
            return CGPoint(x: tailTip.x, y: size.height - 3)
        case .below:
            return CGPoint(x: tailTip.x, y: 3)
        case .leading:
            return CGPoint(x: size.width - 3, y: tailTip.y)
        case .trailing:
            return CGPoint(x: 3, y: tailTip.y)
        }
    }
}

private struct ReaderElfFigure: View {
    let mood: ReaderElfMood
    let blinkScale: CGFloat
    let parked: Bool

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(parked ? 0.08 : 0.14))
                .frame(width: 42, height: 10)
                .offset(y: 34)

            VStack(spacing: -6) {
                ZStack {
                    Capsule()
                        .fill(Color(nsColor: mood.accentColor).opacity(parked ? 0.12 : 0.18))
                        .frame(width: 34, height: 40)

                    HStack(spacing: 10) {
                        eye
                        eye
                    }
                    .offset(y: -3)

                    Capsule()
                        .fill(Color.primary.opacity(parked ? 0.26 : 0.45))
                        .frame(width: 11, height: 2)
                        .offset(y: 7)

                    ElfEar()
                        .fill(Color(nsColor: mood.accentColor).opacity(parked ? 0.72 : 1))
                        .frame(width: 11, height: 18)
                        .rotationEffect(.degrees(-20))
                        .offset(x: -18, y: -2)

                    ElfEar()
                        .fill(Color(nsColor: mood.accentColor).opacity(parked ? 0.72 : 1))
                        .frame(width: 11, height: 18)
                        .scaleEffect(x: -1, y: 1)
                        .rotationEffect(.degrees(20))
                        .offset(x: 18, y: -2)
                }

                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(nsColor: mood.accentColor).opacity(parked ? 0.72 : 1),
                                    Color(nsColor: mood.accentColor).opacity(parked ? 0.46 : 0.68)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 34, height: 34)

                    Triangle()
                        .fill(Color(nsColor: mood.accentColor).opacity(parked ? 0.56 : 0.86))
                        .frame(width: 18, height: 14)
                        .offset(y: -9)
                }
            }
        }
        .scaleEffect(parked ? 0.94 : 1)
    }

    private var eye: some View {
        Capsule()
            .fill(Color.primary.opacity(parked ? 0.48 : 0.8))
            .frame(width: 6, height: 6 * blinkScale)
    }
}

private struct ElfEar: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX * 0.72, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY * 0.75)
        )
        path.closeSubpath()
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct ReaderElfBubbleTail: Shape {
    let placement: ReaderElfBubblePlacement

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch placement {
        case .above:
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.midX, y: rect.minY + 2)
            )
        case .below:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                control: CGPoint(x: rect.midX, y: rect.maxY - 2)
            )
        case .leading:
            path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.minY),
                control: CGPoint(x: rect.minX + 2, y: rect.midY)
            )
        case .trailing:
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.maxX - 2, y: rect.midY)
            )
        }
        path.closeSubpath()
        return path
    }
}
