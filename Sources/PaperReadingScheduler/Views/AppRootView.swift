import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router

    @Query(sort: \Paper.dateAdded, order: .reverse) private var papers: [Paper]
    @Query private var settingsList: [UserSettings]

    @State private var librarySearch = ""
    @State private var libraryStatusFilter = "all"

    private var settings: UserSettings? {
        settingsList.first
    }

    private var selectedPaper: Paper? {
        papers.first(where: { $0.id == router.selectedPaperID })
    }

    private var feedbackSnapshot: FeedbackSnapshot {
        FeedbackSnapshot(
            screen: router.selectedScreen,
            selectedPaper: router.selectedScreen == AppScreen.settings ? nil : selectedPaper
        )
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
            return papers
                .filter { $0.status.isActiveQueue }
                .sorted(by: queueSort)
        case .library:
            return papers
                .filter { $0.status != .archived }
                .filter { paper in
                    libraryStatusFilter == "all" || paper.status.rawValue == libraryStatusFilter
                }
                .filter { $0.matchesSearch(librarySearch) }
                .sorted { $0.dateAdded > $1.dateAdded }
        case .settings:
            return []
        }
    }

    private var displayedPaperIDs: [UUID] {
        displayedPapers.map(\.id)
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
            .sheet(item: readerPresentationBinding) { presentation in
                ReaderView(presentation: presentation)
            }
            .toolbar {
                toolbarContent
            }
            .task {
                await services.bootstrap(in: modelContext, settings: settingsList, papers: papers)
                syncSelectionIfNeeded()
            }
            .onChange(of: router.selectedScreen) { _, _ in
                syncSelectionIfNeeded(forceFirst: true)
            }
            .onChange(of: displayedPaperIDs) { _, _ in
                syncSelectionIfNeeded()
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
            .animation(.snappy(duration: 0.22), value: services.presentedNotice?.id)
    }

    private var navigationView: some View {
        NavigationSplitView {
            sidebar
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
        } else {
            contentColumn
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if router.selectedScreen == AppScreen.settings {
            settingsDetailPlaceholder
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Feedback", systemImage: "square.and.pencil") {
                router.isFeedbackSheetPresented = true
            }

            Button("Add Paper", systemImage: "plus") {
                router.isImportSheetPresented = true
            }

            if let selectedPaper, let settings {
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

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = services.presentedNotice {
            Text(notice.message)
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

            if router.selectedScreen == .library {
                HStack(spacing: 12) {
                    TextField("Search titles, authors, abstracts, or tags", text: $librarySearch)
                        .textFieldStyle(.roundedBorder)
                    Picker("Status", selection: $libraryStatusFilter) {
                        Text("All").tag("all")
                        ForEach(PaperStatus.allCases.filter { $0 != .archived }) { status in
                            Text(status.title).tag(status.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
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
                    ForEach(displayedPapers) { paper in
                        PaperListRow(paper: paper, screen: router.selectedScreen)
                            .tag(Optional(paper.id))
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
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
        case .settings:
            0
        }
    }

    private func sidebarRow(for screen: AppScreen) -> some View {
        Button {
            router.selectedScreen = screen
        } label: {
            HStack {
                Label(screen.title, systemImage: screen.symbolName)
                Spacer()
                if screen != AppScreen.settings {
                    Text(countForScreen(screen).formatted())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(sidebarBackground(for: screen))
        }
        .buttonStyle(.plain)
    }

    private func sidebarBackground(for screen: AppScreen) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(router.selectedScreen == screen ? Color.accentColor.opacity(0.14) : Color.clear)
    }

    private func syncSelectionIfNeeded(forceFirst: Bool = false) {
        guard router.selectedScreen != AppScreen.settings else {
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
}
