import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private let queueDragAnimation = Animation.interactiveSpring(
    response: 0.26,
    dampingFraction: 0.84,
    blendDuration: 0.12
)

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(AgentRuntimeService.self) private var agentRuntime
    @Environment(AppRouter.self) private var router

    @Query(sort: \Paper.dateAdded, order: .reverse) private var papers: [Paper]
    @Query private var settingsList: [UserSettings]

    @State private var librarySearch = ""
    @State private var libraryStatusFilter = "all"
    @State private var draggedQueuePaperID: UUID?
    @State private var queuePreviewPaperIDs: [UUID]?
    @State private var queueDropTargetPaperID: UUID?
    @State private var fusionSession = FusionReactorSession()
    @State private var isImportDropTargeted = false

    private var settings: UserSettings? {
        settingsList.first
    }

    private var selectedPaper: Paper? {
        papers.first(where: { $0.id == router.selectedPaperID })
    }

    private var feedbackSnapshot: FeedbackSnapshot {
        FeedbackSnapshot(
            screen: router.selectedScreen,
            selectedPaper: (
                router.selectedScreen == AppScreen.settings ||
                router.selectedScreen == AppScreen.fusionReactor ||
                router.selectedScreen == AppScreen.hot
            ) ? nil : selectedPaper
        )
    }

    private var fusionSelectedPapers: [Paper] {
        let papersByID = Dictionary(uniqueKeysWithValues: papers.map { ($0.id, $0) })
        return fusionSession.selectedPaperIDs.compactMap { papersByID[$0] }
    }

    private var importSheetBinding: Binding<Bool> {
        Binding(
            get: { router.isImportSheetPresented },
            set: { router.isImportSheetPresented = $0 }
        )
    }

    private var feedbackSheetBinding: Binding<Bool> {
        Binding(
            get: { router.isFeedbackSheetPresented },
            set: { router.isFeedbackSheetPresented = $0 }
        )
    }

    private var readerPresentationBinding: Binding<ReaderPresentation?> {
        Binding(
            get: { router.readerPresentation },
            set: { router.readerPresentation = $0 }
        )
    }

    private var displayedPapers: [Paper] {
        switch router.selectedScreen {
        case .today:
            return papers
                .filter { $0.isDueTodayOrOverdue() }
                .sorted(by: dueDateSort)
        case .inbox:
            return papers
                .filter { $0.status == .inbox }
                .sorted { $0.dateAdded > $1.dateAdded }
        case .queue:
            return queueDisplayPapers
        case .library:
            return papers
                .filter { $0.status != .archived }
                .filter { paper in
                    libraryStatusFilter == "all" || paper.status.rawValue == libraryStatusFilter
                }
                .filter { $0.matchesSearch(librarySearch) }
                .sorted { $0.dateAdded > $1.dateAdded }
        case .hot:
            return []
        case .fusionReactor:
            return []
        case .settings:
            return []
        }
    }

    private var displayedPaperIDs: [UUID] {
        displayedPapers.map(\.id)
    }

    private var queuePapers: [Paper] {
        papers
            .filter { $0.status.isActiveQueue }
            .sorted(by: queueSort)
    }

    private var queueDisplayPapers: [Paper] {
        guard let previewIDs = queuePreviewPaperIDs else {
            return queuePapers
        }

        let papersByID = Dictionary(uniqueKeysWithValues: queuePapers.map { ($0.id, $0) })
        let previewPapers = previewIDs.compactMap { papersByID[$0] }
        let missingPapers = queuePapers.filter { previewIDs.contains($0.id) == false }
        return previewPapers + missingPapers
    }

    private var overdueScheduledQueuePapers: [Paper] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return queuePapers.filter { paper in
            guard paper.status == .scheduled,
                  let dueDate = paper.dueDate else {
                return false
            }
            return calendar.startOfDay(for: dueDate) < today
        }
    }

    var body: some View {
        navigationView
            .sheet(isPresented: importSheetBinding) {
                if let settings {
                    ImportPaperSheet(settings: settings, currentPapers: papers)
                }
            }
            .sheet(isPresented: feedbackSheetBinding) {
                FeedbackCaptureSheet(snapshot: feedbackSnapshot)
            }
            .sheet(item: readerPresentationBinding, content: readerSheet)
            .toolbar {
                toolbarContent
            }
            .task {
                await services.bootstrap(in: modelContext, settings: settingsList, papers: papers)
                services.refreshStorageFolderMonitoring(context: modelContext)
                syncSelectionIfNeeded()
            }
            .onChange(of: settingsMonitorSignature) { _, _ in
                services.refreshStorageFolderMonitoring(context: modelContext)
            }
            .onChange(of: router.selectedScreen) { _, _ in
                if router.selectedScreen != .queue {
                    resetQueueDragState()
                }
                if router.selectedScreen != .fusionReactor {
                    fusionSession.reset()
                }
                syncSelectionIfNeeded(forceFirst: true)
            }
            .onChange(of: displayedPaperIDs) { _, _ in
                syncSelectionIfNeeded()
            }
            .onChange(of: papers.map(\.id)) { _, ids in
                fusionSession.syncMaterials(allowedPaperIDs: Set(ids))
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { services.presentedError != nil },
                    set: { isPresented in
                        if isPresented == false {
                            services.clearPresentedError()
                        }
                    }
                ),
                presenting: services.presentedError
            ) { _ in
                Button("OK") {
                    services.clearPresentedError()
                }
            } message: { error in
                Text(error.message)
            }
            .overlay(alignment: .top) {
                noticeBanner
            }
            .overlay {
                importDropOverlay
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if agentRuntime.isPanelVisible {
                    IntegratedTerminalPanel()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isImportDropTargeted, perform: handleImportedFiles)
            .animation(.snappy(duration: 0.22), value: services.presentedNotice?.id)
    }

    private var settingsMonitorSignature: String {
        guard let settings else { return "settings-unavailable" }
        return [
            settings.paperStorageMode.rawValue,
            settings.customPaperStoragePath
        ].joined(separator: "|")
    }

    @ViewBuilder
    private func readerSheet(for presentation: ReaderPresentation) -> some View {
        if let paper = papers.first(where: { $0.id == presentation.paperID }),
           let settings {
            ReaderView(paper: paper, fileURL: presentation.fileURL, settings: settings)
        } else if papers.contains(where: { $0.id == presentation.paperID }) {
            ProgressView()
                .frame(minWidth: 720, minHeight: 520)
        } else {
            ContentUnavailableView(
                "Paper unavailable",
                systemImage: "doc.slash",
                description: Text("This paper is no longer available in the local library.")
            )
            .frame(minWidth: 720, minHeight: 520)
        }
    }

    private var navigationView: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 196, ideal: 220, max: 260)
        } content: {
            middleColumn
        } detail: {
            detailColumn
        }
    }

    @ViewBuilder
    private var middleColumn: some View {
        if router.selectedScreen == AppScreen.settings {
            if let settings {
                SettingsView(settings: settings, allPapers: papers)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if router.selectedScreen == AppScreen.hot {
            if let settings {
                HotPaperDiscoveryView(
                    papers: papers,
                    settings: settings
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if router.selectedScreen == AppScreen.fusionReactor {
            if let settings {
                PaperFusionReactorView(
                    papers: papers,
                    settings: settings,
                    session: fusionSession
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            contentColumn
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if router.selectedScreen == AppScreen.settings {
            settingsDetailPlaceholder
        } else if router.selectedScreen == AppScreen.hot {
            hotPapersDetailPlaceholder
        } else if router.selectedScreen == AppScreen.fusionReactor {
            if let settings {
                PaperFusionResultView(
                    session: fusionSession,
                    selectedPapers: fusionSelectedPapers,
                    providerReadiness: settings.aiProviderReadiness(apiKey: services.loadTaggingAPIKey())
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if let selectedPaper, let settings {
            PaperDetailView(paper: selectedPaper, settings: settings, allPapers: papers)
        } else {
            ContentUnavailableView(
                "Select a paper",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Choose a paper from the list or import a new one.")
            )
        }
    }

    @ViewBuilder
    private var importDropOverlay: some View {
        if isImportDropTargeted {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.26))
                    .padding(18)

                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 30, weight: .semibold))
                    Text("Drop PDFs to add papers")
                        .font(.title3.weight(.semibold))
                    Text("PaperMaster will import metadata, rename the files, and store them automatically.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Feedback", systemImage: "square.and.pencil") {
                router.isFeedbackSheetPresented = true
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button("Terminal", systemImage: "terminal") {
                if agentRuntime.isPanelVisible {
                    agentRuntime.isPanelVisible = false
                } else {
                    agentRuntime.isPanelVisible = true
                    if agentRuntime.embeddedSessions.isEmpty {
                        _ = agentRuntime.createEmbeddedSession()
                    }
                }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button("Add Paper", systemImage: "plus") {
                router.isImportSheetPresented = true
            }
        }

        if let selectedPaper, let settings {
            ToolbarItem(placement: .primaryAction) {
                Button("Read", systemImage: "book") {
                    Task {
                        router.readerPresentation = await services.prepareReader(
                            for: selectedPaper,
                            currentPapers: papers,
                            settings: settings,
                            context: modelContext
                        )
                    }
                }
                .disabled(selectedPaper.pdfURL == nil && selectedPaper.cachedPDFURL == nil)
            }
        }
    }

    private func handleImportedFiles(_ providers: [NSItemProvider]) -> Bool {
        guard let settings else { return false }

        Task { @MainActor in
            let fileURLs = await loadDroppedFileURLs(from: providers)
            let pdfURLs = fileURLs.filter { $0.pathExtension.lowercased() == "pdf" }
            guard pdfURLs.isEmpty == false else { return }

            await services.importDroppedPDFs(
                at: pdfURLs,
                settings: settings,
                currentPapers: papers,
                in: modelContext
            )
        }

        return true
    }

    private func loadDroppedFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await loadFileURL(from: provider) {
                urls.append(url)
            }
        }
        return urls
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }

                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                if let string = item as? String,
                   let url = URL(string: string) {
                    continuation.resume(returning: url)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private var sidebar: some View {
        List {
            Section {
                ForEach(AppScreen.allCases) { screen in
                    sidebarRow(for: screen)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Reading Desk")
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(router.selectedScreen.title)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                Text(summaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if router.selectedScreen == .queue, let settings, overdueScheduledQueuePapers.isEmpty == false {
                queueReplanBanner(settings: settings)
            }

            if router.selectedScreen == .library {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        librarySearchField
                        libraryStatusPicker
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        librarySearchField
                        HStack(spacing: 12) {
                            libraryStatusPicker
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            if displayedPapers.isEmpty {
                ContentUnavailableView(
                    emptyStateTitle,
                    systemImage: emptyStateSymbol,
                    description: Text(emptyStateMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { router.selectedPaperID },
                    set: { router.selectedPaperID = $0 }
                )) {
                    ForEach(Array(displayedPapers.enumerated()), id: \.element.id) { index, paper in
                        paperRow(for: paper, queueRank: router.selectedScreen == .queue ? index + 1 : nil)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .animation(queueDragAnimation, value: queuePreviewPaperIDs)
                .onDrop(
                    of: [UTType.text],
                    delegate: QueueListDropDelegate(
                        isQueueScreen: router.selectedScreen == .queue,
                        hasActiveDrag: draggedQueuePaperID != nil,
                        commitDrop: commitQueueDrop,
                        resetDragState: resetQueueDragState
                    )
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.08), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var settingsDetailPlaceholder: some View {
        ContentUnavailableView(
            "Scheduler Settings",
            systemImage: "slider.horizontal.3",
            description: Text("Adjust your daily reading capacity, reminder time, and default import behavior from the middle column.")
        )
    }

    private var hotPapersDetailPlaceholder: some View {
        ContentUnavailableView(
            "Spot promising work",
            systemImage: "sparkles.rectangle.stack",
            description: Text("Refresh a category, skim the summaries, and import anything worth tracking into your library.")
        )
    }

    private func queueReplanBanner(settings: UserSettings) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Missed your plan?")
                    .font(.headline)
                Text("Move \(overdueScheduledQueuePapers.count) overdue scheduled \(overdueScheduledQueuePapers.count == 1 ? "paper" : "papers") forward and rebuild the queue from today.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("Replan From Today", systemImage: "calendar.badge.clock") {
                services.replanQueueFromToday(
                    papers: papers,
                    settings: settings,
                    context: modelContext
                )
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var librarySearchField: some View {
        TextField("Fuzzy search titles, authors, keywords, or tags", text: $librarySearch)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 280, maxWidth: .infinity)
    }

    private var libraryStatusPicker: some View {
        HStack(spacing: 10) {
            Text("Status")
                .font(.headline)
                .foregroundStyle(.primary)

            Picker("Status", selection: $libraryStatusFilter) {
                Text("All").tag("all")
                ForEach(PaperStatus.allCases.filter { $0 != .archived }) { status in
                    Text(status.title).tag(status.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var summaryText: String {
        switch router.selectedScreen {
        case .today:
            return "\(displayedPapers.count) papers due or overdue."
        case .inbox:
            return "Captured papers waiting to be scheduled."
        case .queue:
            return "Queue ordered by reading priority and spread across upcoming days."
        case .library:
            return "Browse every active paper, including completed reads and drafts."
        case .hot:
            return ""
        case .fusionReactor:
            return ""
        case .settings:
            return ""
        }
    }

    private var emptyStateTitle: String {
        switch router.selectedScreen {
        case .today:
            "No papers due"
        case .inbox:
            "Inbox is clear"
        case .queue:
            "Queue is empty"
        case .library:
            "No matching papers"
        case .hot:
            ""
        case .fusionReactor:
            ""
        case .settings:
            ""
        }
    }

    private var emptyStateSymbol: String {
        switch router.selectedScreen {
        case .today:
            "checkmark.circle"
        case .inbox:
            "tray"
        case .queue:
            "list.bullet.rectangle"
        case .library:
            "magnifyingglass"
        case .hot:
            "sparkles.rectangle.stack"
        case .fusionReactor:
            "flame"
        case .settings:
            "gearshape"
        }
    }

    private var emptyStateMessage: String {
        switch router.selectedScreen {
        case .today:
            "Your scheduled queue is caught up for today."
        case .inbox:
            "New imports configured for inbox will land here."
        case .queue:
            "Import a paper and schedule it to start building your reading plan."
        case .library:
            "Try a different search query or filter."
        case .hot:
            ""
        case .fusionReactor:
            ""
        case .settings:
            ""
        }
    }

    private func countForScreen(_ screen: AppScreen) -> Int {
        switch screen {
        case .today:
            papers.filter { $0.isDueTodayOrOverdue() }.count
        case .inbox:
            papers.filter { $0.status == .inbox }.count
        case .queue:
            papers.filter { $0.status.isActiveQueue }.count
        case .library:
            papers.filter { $0.status != .archived }.count
        case .hot:
            0
        case .fusionReactor:
            0
        case .settings:
            0
        }
    }

    private func sidebarRow(for screen: AppScreen) -> some View {
        Button {
            router.selectedScreen = screen
        } label: {
            HStack {
                Label(screen.sidebarTitle, systemImage: screen.symbolName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if screen != AppScreen.settings && screen != AppScreen.fusionReactor && screen != AppScreen.hot {
                    Text(countForScreen(screen).formatted())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(sidebarBackground(for: screen))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sidebarBackground(for screen: AppScreen) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(router.selectedScreen == screen ? Color.accentColor.opacity(0.14) : Color.clear)
    }

    private func syncSelectionIfNeeded(forceFirst: Bool = false) {
        guard router.selectedScreen != AppScreen.settings,
              router.selectedScreen != AppScreen.fusionReactor,
              router.selectedScreen != AppScreen.hot else {
            router.selectedPaperID = nil
            return
        }

        guard forceFirst || displayedPaperIDs.contains(router.selectedPaperID ?? UUID()) == false else {
            return
        }

        router.selectedPaperID = displayedPapers.first?.id
    }

    private func queueSort(lhs: Paper, rhs: Paper) -> Bool {
        if lhs.queuePosition != rhs.queuePosition {
            return lhs.queuePosition < rhs.queuePosition
        }
        return lhs.dateAdded < rhs.dateAdded
    }

    private func dueDateSort(lhs: Paper, rhs: Paper) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?):
            if left != right {
                return left < right
            }
            return queueSort(lhs: lhs, rhs: rhs)
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return queueSort(lhs: lhs, rhs: rhs)
        }
    }

    @ViewBuilder
    private func paperRow(for paper: Paper, queueRank: Int?) -> some View {
        let row = PaperListRow(
            paper: paper,
            screen: router.selectedScreen,
            queueRank: queueRank,
            isDragging: draggedQueuePaperID == paper.id,
            isDropTarget: queueDropTargetPaperID == paper.id
        )
        .tag(Optional(paper.id))
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                router.selectedPaperID = paper.id
            }
        )

        if router.selectedScreen == .queue, paper.status.isActiveQueue {
            row
                .onDrag { beginQueueDrag(for: paper) }
                .onDrop(
                    of: [UTType.text],
                    delegate: QueueRowDropDelegate(
                        targetPaperID: paper.id,
                        draggedPaperID: draggedQueuePaperID,
                        updatePreview: { moveQueuePreview(hoveringOver: paper.id) },
                        commitDrop: commitQueueDrop,
                        clearDropTarget: clearQueueDropTarget(_:)
                    )
                )
        } else {
            row
        }
    }

    private func beginQueueDrag(for paper: Paper) -> NSItemProvider {
        draggedQueuePaperID = paper.id
        queuePreviewPaperIDs = queuePapers.map(\.id)
        queueDropTargetPaperID = nil
        return NSItemProvider(object: paper.id.uuidString as NSString)
    }

    private func moveQueuePreview(hoveringOver targetPaperID: UUID) {
        guard let draggedQueuePaperID,
              draggedQueuePaperID != targetPaperID,
              let draggedOriginalIndex = queuePapers.firstIndex(where: { $0.id == draggedQueuePaperID }),
              let targetOriginalIndex = queuePapers.firstIndex(where: { $0.id == targetPaperID }) else {
            return
        }

        if queuePreviewPaperIDs == nil {
            queuePreviewPaperIDs = queuePapers.map(\.id)
        }

        guard let previewIDs = queuePreviewPaperIDs else { return }
        guard queueDropTargetPaperID != targetPaperID else { return }

        queueDropTargetPaperID = targetPaperID

        guard let reorderedPreview = QueueDragPreview.reorderedIDs(
            from: previewIDs,
            draggedID: draggedQueuePaperID,
            targetID: targetPaperID,
            insertAfterTarget: targetOriginalIndex > draggedOriginalIndex
        ) else { return }

        withAnimation(queueDragAnimation) {
            queuePreviewPaperIDs = reorderedPreview
        }
    }

    private func commitQueueDrop() {
        defer { resetQueueDragState() }

        guard let draggedQueuePaperID,
              let previewIDs = queuePreviewPaperIDs,
              let destinationIndex = previewIDs.firstIndex(of: draggedQueuePaperID),
              let paper = papers.first(where: { $0.id == draggedQueuePaperID }),
              let settings else {
            return
        }

        services.move(
            paper: paper,
            toQueueIndex: destinationIndex,
            allPapers: papers,
            settings: settings,
            context: modelContext
        )
    }

    private func clearQueueDropTarget(_ targetPaperID: UUID) {
        guard queueDropTargetPaperID == targetPaperID else { return }
        queueDropTargetPaperID = nil
    }

    private func resetQueueDragState() {
        draggedQueuePaperID = nil
        queuePreviewPaperIDs = nil
        queueDropTargetPaperID = nil
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let message = services.importStatusMessage ?? services.presentedNotice?.message {
            Text(message)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.12), radius: 14, y: 8)
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

}

private struct QueueRowDropDelegate: DropDelegate {
    let targetPaperID: UUID
    let draggedPaperID: UUID?
    let updatePreview: () -> Void
    let commitDrop: () -> Void
    let clearDropTarget: (UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedPaperID != nil
    }

    func dropEntered(info: DropInfo) {
        guard draggedPaperID != nil else { return }
        updatePreview()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggedPaperID != nil else { return nil }
        updatePreview()
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        clearDropTarget(targetPaperID)
    }

    func performDrop(info: DropInfo) -> Bool {
        commitDrop()
        return true
    }
}

private struct QueueListDropDelegate: DropDelegate {
    let isQueueScreen: Bool
    let hasActiveDrag: Bool
    let commitDrop: () -> Void
    let resetDragState: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        isQueueScreen && hasActiveDrag
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        resetDragState()
    }

    func performDrop(info: DropInfo) -> Bool {
        guard hasActiveDrag else { return false }
        commitDrop()
        return true
    }
}

struct QueueDragPreview {
    static func reorderedIDs(
        from previewIDs: [UUID],
        draggedID: UUID,
        targetID: UUID,
        insertAfterTarget: Bool
    ) -> [UUID]? {
        guard draggedID != targetID,
              let currentIndex = previewIDs.firstIndex(of: draggedID),
              let targetIndex = previewIDs.firstIndex(of: targetID) else {
            return nil
        }

        var reorderedIDs = previewIDs
        let movedID = reorderedIDs.remove(at: currentIndex)
        let destinationIndex: Int
        if currentIndex < targetIndex {
            destinationIndex = insertAfterTarget ? targetIndex : max(0, targetIndex - 1)
        } else {
            destinationIndex = insertAfterTarget ? min(reorderedIDs.count, targetIndex + 1) : targetIndex
        }
        reorderedIDs.insert(movedID, at: destinationIndex)

        guard reorderedIDs != previewIDs else { return nil }
        return reorderedIDs
    }
}
