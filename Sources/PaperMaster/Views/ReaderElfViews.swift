import SwiftUI

struct ReaderElfPaneOverlayView: View {
    let state: ReaderElfOverlayState

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                let resolvedState = stateWithPaneBounds(CGRect(origin: .zero, size: proxy.size))
                let layout = ReaderElfOverlayLayout.resolve(for: resolvedState)
                let timestamp = context.date.timeIntervalSinceReferenceDate
                let bob = sin(timestamp * 2.8) * (resolvedState.activeComment == nil ? 1.8 : 3.0)
                let blinkValue = abs(sin(timestamp * 1.55))
                let blinkScale = blinkValue > 0.985 ? 0.18 : 1.0

                ZStack(alignment: .topLeading) {
                    if let comment = resolvedState.activeComment,
                       let bubbleFrame = layout.bubbleFrame,
                       let bubblePlacement = layout.bubblePlacement {
                        ReaderElfBubble(
                            comment: comment,
                            placement: bubblePlacement,
                            tailTip: layout.tailTip.map { tip in
                                CGPoint(x: tip.x - bubbleFrame.minX, y: tip.y - bubbleFrame.minY)
                            }
                        )
                            .frame(width: bubbleFrame.width, height: bubbleFrame.height, alignment: .topLeading)
                            .offset(x: bubbleFrame.minX, y: bubbleFrame.minY)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }

                    ReaderElfFigure(
                        mood: figureMood(for: resolvedState),
                        blinkScale: blinkScale,
                        parked: resolvedState.status == .off
                    )
                    .frame(width: layout.figureFrame.width, height: layout.figureFrame.height)
                    .opacity(figureOpacity(for: resolvedState.status))
                    .offset(x: layout.figureFrame.minX, y: layout.figureFrame.minY + bob)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(.snappy(duration: 0.34, extraBounce: 0.14), value: animationKey(for: resolvedState, layout: layout))
            }
        }
        .allowsHitTesting(false)
        .background(Color.clear)
    }

    private func stateWithPaneBounds(_ paneBounds: CGRect) -> ReaderElfOverlayState {
        ReaderElfOverlayState(
            status: state.status,
            activeComment: state.activeComment,
            dockCorner: state.dockCorner,
            geometry: ReaderElfGeometrySnapshot(
                paneBounds: paneBounds,
                pageFrame: state.pageFrame,
                anchorFrame: state.anchorFrame
            ),
            preferredBubblePlacement: state.preferredBubblePlacement
        )
    }

    private func figureMood(for state: ReaderElfOverlayState) -> ReaderElfMood {
        if let activeComment = state.activeComment {
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

    private func figureOpacity(for status: ReaderElfStatus) -> Double {
        switch status {
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

    private func animationKey(for state: ReaderElfOverlayState, layout: ReaderElfOverlayLayout) -> String {
        [
            state.activeComment?.id.uuidString ?? "idle",
            state.status.title,
            "\(layout.figureFrame.minX.rounded())",
            "\(layout.figureFrame.minY.rounded())",
            "\(layout.bubbleFrame?.minX.rounded() ?? -1)",
            "\(layout.bubbleFrame?.minY.rounded() ?? -1)"
        ].joined(separator: ":")
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
