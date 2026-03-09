import SwiftUI
import UniformTypeIdentifiers

struct PaperFusionReactorView: View {
    @Environment(AppServices.self) private var services

    let papers: [Paper]
    let settings: UserSettings
    @Bindable var session: FusionReactorSession

    @State private var searchText = ""
    @State private var isDropTargeted = false
    @State private var storedAPIKey = ""
    @State private var successPulse = false

    private var sourcePapers: [Paper] {
        papers
            .filter { $0.status != .archived }
            .filter { $0.matchesSearch(searchText) }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    private var selectedPapers: [Paper] {
        let papersByID = Dictionary(uniqueKeysWithValues: papers.map { ($0.id, $0) })
        return session.selectedPaperIDs.compactMap { papersByID[$0] }
    }

    private var providerReadiness: AIProviderReadiness {
        settings.aiProviderReadiness(apiKey: storedAPIKey)
    }

    private var canIgnite: Bool {
        if case .ready = providerReadiness {
            return session.canFuse
        }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            sourceShelf
            reactorStage
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.16),
                    Color.red.opacity(0.06),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .task {
            storedAPIKey = services.loadTaggingAPIKey()
        }
        .onChange(of: session.result?.generatedAt) { _, newValue in
            guard newValue != nil else { return }
            triggerSuccessPulse()
        }
    }

    private var sourceShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Paper Fusion Reactor")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                Text("Drag at least two papers into the furnace and let the backend combine them into new research directions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextField("Search titles, authors, abstracts, or tags", text: $searchText)
                .textFieldStyle(.roundedBorder)

            Text("\(sourcePapers.count) papers available as reactor material")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sourcePapers) { paper in
                        FusionSourcePaperCard(
                            paper: paper,
                            isSelected: session.selectedPaperIDs.contains(paper.id)
                        )
                        .onDrag {
                            NSItemProvider(object: paper.id.uuidString as NSString)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 380, maxHeight: .infinity, alignment: .topLeading)
    }

    private var reactorStage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Alchemy Furnace")
                        .font(.title2.weight(.semibold))
                    Text("The furnace accepts 2 to 6 papers. Change the materials and the prior result is cleared.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Clear Materials") {
                    session.clearMaterials()
                }
                .disabled(session.selectedPaperIDs.isEmpty)
            }

            materialTray

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.14),
                                Color.orange.opacity(isDropTargeted ? 0.18 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(
                                isDropTargeted ? Color.orange.opacity(0.7) : Color.primary.opacity(0.08),
                                lineWidth: isDropTargeted ? 2 : 1
                            )
                    )

                VStack(spacing: 16) {
                    FusionFurnaceView(
                        isActive: session.isFusing,
                        isDropTargeted: isDropTargeted,
                        materialCount: session.selectedPaperIDs.count,
                        successPulse: successPulse,
                        isIgnitable: canIgnite,
                        igniteAction: startFusion
                    )
                    .frame(maxWidth: .infinity)

                    Text(dropHintText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(isDropTargeted ? Color.orange : .secondary)
                }
                .padding(28)
            }
            .frame(maxWidth: .infinity, minHeight: 420)
            .onDrop(of: [UTType.text], isTargeted: $isDropTargeted, perform: handleMaterialDrop(providers:))

            HStack {
                if case .ready = providerReadiness {
                    Label("Click the fire to start fusion", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Label(providerReadiness.settingsMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var materialTray: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Loaded Materials")
                    .font(.headline)
                Spacer()
                Text("\(session.selectedPaperIDs.count)/\(FusionMaterialSelection.maximumPaperCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(session.selectedPaperIDs.count >= FusionMaterialSelection.maximumPaperCount ? .orange : .secondary)
            }

            if selectedPapers.isEmpty {
                ContentUnavailableView(
                    "No papers in the furnace yet",
                    systemImage: "sparkles.square.filled.on.square",
                    description: Text("Drag papers from the shelf into the furnace to start combining ideas.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                    ForEach(selectedPapers) { paper in
                        SelectedFusionMaterialChip(paper: paper) {
                            session.removeMaterial(paper.id)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .animation(.snappy(duration: 0.22), value: session.selectedPaperIDs)
    }

    private var dropHintText: String {
        if session.isFusing {
            return "Refining in progress..."
        }
        if session.selectedPaperIDs.count < FusionMaterialSelection.minimumPaperCount {
            return "Add at least two papers, then click the fire to begin fusion."
        }
        if session.selectedPaperIDs.count >= FusionMaterialSelection.maximumPaperCount {
            return "Reactor capacity reached. Remove a paper before adding more."
        }
        return "The furnace is primed. Click the fire to start refining."
    }

    private func handleMaterialDrop(providers: [NSItemProvider]) -> Bool {
        guard providers.isEmpty == false else { return false }

        Task {
            for provider in providers {
                guard let identifier = await provider.loadDroppedText(),
                      let paperID = UUID(uuidString: identifier) else {
                    continue
                }

                switch session.addMaterial(paperID) {
                case .added, .duplicate:
                    continue
                case .limitReached:
                    services.showNotice("The furnace can only hold \(FusionMaterialSelection.maximumPaperCount) papers.")
                    return
                }
            }
        }

        return true
    }

    private func triggerSuccessPulse() {
        successPulse = true
        Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            await MainActor.run {
                successPulse = false
            }
        }
    }

    private func startFusion() {
        guard canIgnite else { return }

        Task {
            session.beginFusion()
            let result = await services.fusePapers(selectedPapers, settings: settings)
            session.finishFusion(with: result)
        }
    }
}

struct PaperFusionResultView: View {
    @Bindable var session: FusionReactorSession
    let selectedPapers: [Paper]
    let providerReadiness: AIProviderReadiness

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if session.isFusing {
                    loadingState
                } else if let result = session.result {
                    resultsState(result)
                } else if case .ready = providerReadiness {
                    emptyState
                } else {
                    configurationState
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.10), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Refining research ideas...", systemImage: "sparkles")
                .font(.title3.weight(.semibold))

            ProgressView()

            Text("The backend is looking for realistic bridges between the loaded papers.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if selectedPapers.isEmpty == false {
                selectedPaperSummary
            }
        }
    }

    private func resultsState(_ result: PaperFusionResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Fusion Results")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                Text("Three candidate research directions generated from the current paper materials.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            selectedPaperSummary

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(result.ideas.enumerated()), id: \.element.id) { index, idea in
                    FusionIdeaCard(index: index + 1, idea: idea)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Awaiting materials",
            systemImage: "flame",
            description: Text("Load papers into the reactor and start refining to see combined research ideas here.")
        )
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var configurationState: some View {
        ContentUnavailableView(
            "AI provider setup required",
            systemImage: "gearshape.2",
            description: Text("\(providerReadiness.settingsMessage) Open Settings to finish the shared AI provider setup used by Fusion Reactor.")
        )
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var selectedPaperSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current Materials")
                .font(.headline)

            ForEach(selectedPapers) { paper in
                VStack(alignment: .leading, spacing: 4) {
                    Text(paper.title)
                        .font(.subheadline.weight(.semibold))
                    Text(paper.authorsDisplayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct FusionSourcePaperCard: View {
    let paper: Paper
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(paper.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(paper.authorsDisplayText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Label(isSelected ? "Loaded" : "Drag", systemImage: isSelected ? "checkmark.circle.fill" : "hand.draw")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .green : .orange)
            }

            if paper.tagNames.isEmpty == false {
                HStack(spacing: 8) {
                    ForEach(Array(paper.tagNames.prefix(3)), id: \.self) { tag in
                        TagChip(name: tag)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color.orange.opacity(0.10) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.orange.opacity(0.36) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct SelectedFusionMaterialChip: View {
    let paper: Paper
    let removeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(paper.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button(action: removeAction) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(paper.authorsDisplayText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
    }
}

private struct FusionIdeaCard: View {
    let index: Int
    let idea: PaperFusionIdea

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Idea \(index)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
            }

            Text(idea.title)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Core Hypothesis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(idea.hypothesis)
                    .font(.body)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Why These Papers Fit")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(idea.rationale)
                    .font(.body)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.14),
                            Color.red.opacity(0.08),
                            Color.primary.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct FusionFurnaceView: View {
    let isActive: Bool
    let isDropTargeted: Bool
    let materialCount: Int
    let successPulse: Bool
    let isIgnitable: Bool
    let igniteAction: () -> Void

    var body: some View {
        TimelineView(.animation) { context in
            let timestamp = context.date.timeIntervalSinceReferenceDate
            let flicker = 0.84 + (sin(timestamp * 5.4) * 0.16)
            let glow = 0.78 + (sin(timestamp * 2.6) * 0.12)
            let shakeOffset = isActive ? sin(timestamp * 26) * 3.5 : 0
            let emberTravel = isActive ? (timestamp.truncatingRemainder(dividingBy: 1.6) / 1.6) : 0.2
            let fireScale = isActive ? 1.14 : (isIgnitable ? 1.0 : 0.90)
            let fireOpacity = isIgnitable || isActive ? 1.0 : 0.58

            ZStack {
                if successPulse {
                    Circle()
                        .stroke(Color.orange.opacity(0.45), lineWidth: 6)
                        .frame(width: 250, height: 250)
                        .scaleEffect(1.0 + (isActive ? 0.05 : 0.12))
                        .blur(radius: 1.5)
                }

                Circle()
                    .fill(Color.orange.opacity(isDropTargeted ? 0.20 : 0.10))
                    .frame(width: 250, height: 250)
                    .blur(radius: isDropTargeted ? 8 : 14)

                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(Color.orange.opacity(isActive ? 0.32 : 0.14))
                        .frame(width: 10, height: 10)
                        .offset(
                            x: CGFloat(index - 1) * 26,
                            y: CGFloat(-25 - (emberTravel * 80) - Double(index * 10))
                        )
                        .blur(radius: 1)
                }

                VStack(spacing: -4) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.42, green: 0.24, blue: 0.16), Color(red: 0.22, green: 0.14, blue: 0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 190, height: 42)
                        .overlay(
                            Capsule()
                                .stroke(Color.orange.opacity(0.24), lineWidth: 1.2)
                        )

                    ZStack {
                        RoundedRectangle(cornerRadius: 42, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.36, green: 0.21, blue: 0.12),
                                        Color(red: 0.17, green: 0.11, blue: 0.10),
                                        Color(red: 0.07, green: 0.06, blue: 0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 220, height: 214)
                            .overlay(
                                RoundedRectangle(cornerRadius: 42, style: .continuous)
                                    .stroke(Color.orange.opacity(0.28), lineWidth: 1.4)
                            )

                        VStack(spacing: 14) {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color.orange.opacity(0.82 * glow),
                                            Color.red.opacity(0.46 * glow),
                                            Color.black.opacity(0.18)
                                        ],
                                        center: .center,
                                        startRadius: 8,
                                        endRadius: 54
                                    )
                                )
                                .frame(width: 98, height: 98)
                                .overlay(
                                    Text("\(materialCount)")
                                        .font(.system(size: 30, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.92))
                                )

                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 120, height: 12)
                        }
                    }

                    HStack(spacing: 54) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(red: 0.20, green: 0.12, blue: 0.10))
                            .frame(width: 22, height: 62)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(red: 0.20, green: 0.12, blue: 0.10))
                            .frame(width: 22, height: 62)
                    }
                }
                .offset(x: shakeOffset)

                Button(action: igniteAction) {
                    ZStack {
                        Ellipse()
                            .fill(Color.orange.opacity(isIgnitable || isActive ? 0.22 : 0.10))
                            .frame(width: 210, height: 36)
                            .blur(radius: 8)

                        Ellipse()
                            .fill(Color.orange.opacity(0.72 * flicker))
                            .frame(width: 110, height: 72)
                            .offset(y: -6)

                        Ellipse()
                            .fill(Color.red.opacity(0.78 * flicker))
                            .frame(width: 70, height: 48)
                            .offset(y: -2)

                        Ellipse()
                            .fill(Color.yellow.opacity(0.84 * flicker))
                            .frame(width: 34, height: 26)
                            .offset(y: 4)

                        if isIgnitable && isActive == false {
                            Circle()
                                .stroke(Color.orange.opacity(0.36), lineWidth: 2)
                                .frame(width: 122, height: 84)
                                .blur(radius: 0.5)
                        }
                    }
                    .contentShape(Ellipse())
                }
                .buttonStyle(.plain)
                .disabled(isIgnitable == false)
                .help(isIgnitable ? "Start fusion" : "Load at least two papers and configure the AI provider to ignite the furnace.")
                .offset(y: 148)
                .scaleEffect(fireScale)
                .opacity(fireOpacity)
            }
            .frame(width: 320, height: 360)
        }
    }
}

private extension NSItemProvider {
    func loadDroppedText() async -> String? {
        await withCheckedContinuation { continuation in
            guard hasItemConformingToTypeIdentifier(UTType.text.identifier) else {
                continuation.resume(returning: nil)
                return
            }

            loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let string = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: string)
                    return
                }

                if let string = item as? String {
                    continuation.resume(returning: string)
                    return
                }

                if let string = item as? NSString {
                    continuation.resume(returning: string as String)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }
}
