import SwiftData
import SwiftUI

struct HotPaperDiscoveryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router

    let papers: [Paper]
    let settings: UserSettings
    let discoveryService: HotPaperDiscovering

    @State private var selectedCategory: HotPaperCategory = .machineLearning
    @State private var discoveredPapers: [HotPaper] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var importingPaperIDs: Set<String> = []

    init(
        papers: [Paper],
        settings: UserSettings,
        discoveryService: HotPaperDiscovering = ArXivHotPaperDiscoveryService()
    ) {
        self.papers = papers
        self.settings = settings
        self.discoveryService = discoveryService
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let errorMessage {
                ContentUnavailableView(
                    "Could not load hot papers",
                    systemImage: "wifi.exclamationmark",
                    description: Text(errorMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading && discoveredPapers.isEmpty {
                ProgressView("Loading hot papers...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if discoveredPapers.isEmpty {
                ContentUnavailableView(
                    "No hot papers yet",
                    systemImage: "sparkles",
                    description: Text("Refresh the feed to pull the latest arXiv submissions.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(discoveredPapers) { paper in
                            hotPaperCard(for: paper)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color.yellow.opacity(0.12), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .task(id: selectedCategory) {
            await refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hot Papers")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                    Text(selectedCategory.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button {
                    Task {
                        await refresh()
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }

            Picker("Category", selection: $selectedCategory) {
                ForEach(HotPaperCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var librarySignals: [String] {
        papers.compactMap(\.venueKey) + papers.compactMap(\.venueName) + papers.flatMap(\.tagNames)
    }

    private func hotPaperCard(for paper: HotPaper) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(paper.title)
                        .font(.title3.weight(.semibold))
                    Text(paper.authorsText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    scoreBadge(for: paper)
                    Text(relativeDateText(for: paper.publishedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if paper.reasons.isEmpty == false {
                FlexibleTagWrap(tags: paper.reasons)
            }

            Text(paper.summary)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(5)

            HStack(spacing: 10) {
                Button {
                    Task {
                        await importHotPaper(paper)
                    }
                } label: {
                    if importingPaperIDs.contains(paper.id) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 88)
                    } else {
                        Label("Import", systemImage: "plus.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(importingPaperIDs.contains(paper.id))

                Link(destination: paper.sourceURL) {
                    Label("Open Abstract", systemImage: "safari")
                }
                .buttonStyle(.bordered)

                if let pdfURL = paper.pdfURL {
                    Link(destination: pdfURL) {
                        Label("PDF", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.orange.opacity(0.14), lineWidth: 1)
        )
    }

    private func scoreBadge(for paper: HotPaper) -> some View {
        Text("\(paper.scoreLabel) \(Int((paper.score * 100).rounded()))")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.14), in: Capsule())
    }

    private func relativeDateText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Published \(formatter.localizedString(for: date, relativeTo: .now))"
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            discoveredPapers = try await discoveryService.discoverPapers(
                in: selectedCategory,
                librarySignals: librarySignals
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    private func importHotPaper(_ hotPaper: HotPaper) async {
        importingPaperIDs.insert(hotPaper.id)
        defer { importingPaperIDs.remove(hotPaper.id) }

        let request = PaperCaptureRequest(
            sourceText: hotPaper.sourceURL.absoluteString,
            manualTitle: hotPaper.title,
            manualAuthors: hotPaper.authors.joined(separator: ", "),
            manualAbstract: hotPaper.summary,
            tagNames: [selectedCategory.title.lowercased()],
            preferredBehavior: .addToInbox
        )

        if let importedPaper = await services.importPaper(
            request: request,
            settings: settings,
            currentPapers: papers,
            in: modelContext
        ) {
            router.selectedScreen = .library
            router.selectedPaperID = importedPaper.id
        }
    }
}

private struct FlexibleTagWrap: View {
    let tags: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    tagView(tag)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    tagView(tag)
                }
            }
        }
    }

    private func tagView(_ tag: String) -> some View {
        Text(tag)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}
