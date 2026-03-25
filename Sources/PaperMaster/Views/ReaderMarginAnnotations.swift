import SwiftUI

struct ReaderMarginAnnotationOverlayView: View {
    let geometry: ReaderMarginAnnotationGeometry
    let annotations: [PaperAnnotation]
    let appearanceMode: ReaderAppearanceMode
    @Binding var expandedCardID: UUID?
    @Binding var spotlightedCardID: UUID?
    let onJumpToAnnotation: (UUID) -> Void
    let onDeleteAnnotation: (PaperAnnotation) -> Void
    let onUpdateColor: (PaperAnnotation, ReaderHighlightColor) -> Void
    let noteBindingProvider: (PaperAnnotation) -> Binding<String>
    let focusedField: FocusState<ReaderMarginFocusField?>.Binding
    let onNoteFocusChanged: (UUID?) -> Void

    @State private var cardHeights: [UUID: CGFloat] = [:]

    var body: some View {
        let layout = ReaderMarginAnnotationLayout.resolve(
            geometry: geometry,
            expandedCardID: expandedCardID,
            cardHeights: cardHeights
        )
        let annotationsByID = Dictionary(uniqueKeysWithValues: annotations.map { ($0.id, $0) })

        ZStack(alignment: .topLeading) {
            ReaderMarginLeaderLinesCanvas(
                cards: layout.cards,
                spotlightedID: spotlightedCardID,
                appearanceMode: appearanceMode
            )

            ForEach(layout.cards) { card in
                if let annotation = annotationsByID[card.id] {
                    let isExpanded = expandedCardID == card.id
                    let isSpotlighted = spotlightedCardID == card.id

                    ReaderMarginAnnotationCard(
                        annotation: annotation,
                        isExpanded: isExpanded,
                        isSpotlighted: isSpotlighted,
                        isCompact: card.isCompact,
                        noteBinding: noteBindingProvider(annotation),
                        focusedField: focusedField,
                        onTap: {
                            withAnimation(.snappy(duration: 0.18)) {
                                expandedCardID = (expandedCardID == card.id) ? nil : card.id
                            }
                        },
                        onJump: { onJumpToAnnotation(card.id) },
                        onDelete: { onDeleteAnnotation(annotation) },
                        onColorChange: { onUpdateColor(annotation, $0) },
                        onNoteFocusChanged: onNoteFocusChanged
                    )
                    .frame(width: card.cardFrame.width)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: MarginCardHeightPreferenceKey.self,
                                value: [card.id: proxy.size.height]
                            )
                        }
                    )
                    .offset(x: card.cardFrame.minX, y: card.cardFrame.minY)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onPreferenceChange(MarginCardHeightPreferenceKey.self) { heights in
            let validIDs = Set(annotations.map(\.id))
            cardHeights = cardHeights.filter { validIDs.contains($0.key) }
            cardHeights.merge(heights) { _, new in new }
        }
        .animation(.snappy(duration: 0.22), value: expandedCardID)
        .animation(.snappy(duration: 0.18), value: spotlightedCardID)
    }
}

enum ReaderMarginFocusField: Hashable {
    case marginNote(UUID)
}

struct ReaderMarginAnnotationCard: View {
    let annotation: PaperAnnotation
    let isExpanded: Bool
    let isSpotlighted: Bool
    let isCompact: Bool
    @Binding var noteBinding: String
    let focusedField: FocusState<ReaderMarginFocusField?>.Binding
    let onTap: () -> Void
    let onJump: () -> Void
    let onDelete: () -> Void
    let onColorChange: (ReaderHighlightColor) -> Void
    let onNoteFocusChanged: (UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(nsColor: annotation.color.pdfColor).opacity(0.95))
                .frame(width: 3)
                .padding(.vertical, 6)
                .padding(.leading, 6)
        }
        .overlay(cardBorder)
        .shadow(
            color: .black.opacity(isSpotlighted ? 0.12 : 0.06),
            radius: isSpotlighted ? 8 : 4,
            y: isSpotlighted ? 4 : 2
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var collapsedContent: some View {
        Text(annotation.notePreviewText)
            .font(.caption2)
            .fontWeight(.medium)
            .lineLimit(2)
            .foregroundStyle(.primary.opacity(0.85))
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Page \(annotation.pageNumber)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()

                cardActions
            }

            noteEditor
        }
    }

    private var cardActions: some View {
        HStack(spacing: 6) {
            ForEach(ReaderHighlightColor.allCases) { color in
                Button {
                    onColorChange(color)
                } label: {
                    Circle()
                        .fill(Color(nsColor: color.pdfColor))
                        .frame(width: 12, height: 12)
                        .overlay {
                            if annotation.color == color {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.7), lineWidth: 1.5)
                                    .padding(-1.5)
                            }
                        }
                }
                .buttonStyle(.plain)
            }

            Divider()
                .frame(height: 12)

            Button {
                onJump()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help("Jump to highlight")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help("Delete highlight")
        }
    }

    private var noteEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $noteBinding)
                .focused(focusedField, equals: .marginNote(annotation.id))
                .font(.caption)
                .scrollContentBackground(.hidden)
                .onChange(of: focusedField.wrappedValue) { _, newValue in
                    if case .marginNote(let id) = newValue, id == annotation.id {
                        onNoteFocusChanged(annotation.id)
                    } else if focusedField.wrappedValue != .marginNote(annotation.id) {
                        onNoteFocusChanged(nil)
                    }
                }

            if annotation.hasNote == false {
                Text("Add a note…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 7)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 40, maxHeight: 60)
        .padding(6)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private var cardBackground: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.92)
    }

    @ViewBuilder
    private var cardBorder: some View {
        if isSpotlighted {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: annotation.color.pdfColor).opacity(0.8), lineWidth: 2)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }
}

struct ReaderMarginLeaderLinesCanvas: View {
    let cards: [ReaderMarginAnnotationLayout.CardLayout]
    let spotlightedID: UUID?
    let appearanceMode: ReaderAppearanceMode

    var body: some View {
        Canvas { context, size in
            for card in cards {
                let start = card.leaderStartPoint
                let end = card.leaderEndPoint

                guard start.x < end.x else { continue }

                let isSpotlighted = card.id == spotlightedID
                let baseColor = Color(nsColor: card.annotationColor.pdfColor)
                let lineOpacity: Double = isSpotlighted ? 0.95 : 0.7
                let lineWidth: CGFloat = isSpotlighted ? 2.5 : 1.8

                let controlXFraction: CGFloat = 0.6
                let controlX = start.x + (end.x - start.x) * controlXFraction

                var path = Path()
                path.move(to: start)
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: controlX, y: start.y),
                    control2: CGPoint(x: controlX, y: end.y)
                )

                context.stroke(
                    path,
                    with: .color(baseColor.opacity(lineOpacity)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

                let dotRadius: CGFloat = isSpotlighted ? 4.5 : 3.5
                let dotRect = CGRect(
                    x: start.x - dotRadius,
                    y: start.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                context.fill(
                    Circle().path(in: dotRect),
                    with: .color(baseColor.opacity(isSpotlighted ? 0.95 : 0.75))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MarginCardHeightPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
