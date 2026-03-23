import AppKit
import PDFKit
import SwiftData
import SwiftUI

struct ReaderView: View {
    @AppStorage("reader.lastHighlightColor") private var lastHighlightColorRawValue = ReaderHighlightColor.yellow.rawValue
    @AppStorage("reader.elf.enabled") private var readerElfEnabled = true
    @AppStorage("reader.displayMode") private var displayModeRawValue = ReaderDisplayMode.singleContinuous.rawValue
    @AppStorage("reader.appearance") private var appearanceModeRawValue = ReaderAppearanceMode.normal.rawValue
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @Bindable var paper: Paper
    let fileURL: URL
    let settings: UserSettings

    @FocusState private var focusedField: ReaderFocusField?
    @State private var selectionState: ReaderPDFSelectionState = .none
    @State private var focusPassage: ReaderFocusPassageSnapshot?
    @State private var elfOverlayGeometry: ReaderElfGeometrySnapshot?
    @State private var elfOverlayViewportActivityAt: Date?
    @State private var isSidebarVisible = true
    @State private var expandedAnnotationID: UUID?
    @State private var pdfCommand: ReaderPDFCommand?
    @State private var askAISession = ReaderAskAISessionState()
    @State private var elfSession = ReaderElfSessionState()
    @State private var elfPresentation = ReaderElfPresentationState()
    @State private var elfOverlayCaptureToken = UUID()
    @State private var cachedDocumentContext: ReaderAskAIDocumentContext?
    @State private var askAITask: Task<Void, Never>?
    @State private var elfScheduleTask: Task<Void, Never>?
    @State private var elfTask: Task<Void, Never>?
    @State private var elfCaptureTask: Task<Void, Never>?
    @State private var elfResolveTask: Task<Void, Never>?
    @State private var elfPhaseTask: Task<Void, Never>?
    @State private var elfDismissTask: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?
    @State private var spotlightDismissTask: Task<Void, Never>?
    @State private var sidebarRevealCommand: ReaderSidebarRevealCommand?
    @State private var spotlightedAnnotationID: UUID?
    @State private var currentScaleFactor: CGFloat = 1.0
    @State private var currentPageIndex: Int = 0
    @State private var totalPageCount: Int = 0
    @State private var isSearchBarVisible = false
    @State private var searchText = ""
    @State private var searchResults: [PDFSelection] = []
    @State private var currentSearchResultIndex: Int = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var isGoToPagePopoverVisible = false
    @State private var goToPageText = ""
    @State private var isThumbnailSidebarVisible = false
    @State private var outlineItems: [ReaderOutlineItem] = []
    @State private var thumbnailSidebarTab: ThumbnailSidebarTab = .thumbnails
    @State private var pdfViewReference = PDFViewReference()

    private var selectedDisplayMode: ReaderDisplayMode {
        get { ReaderDisplayMode(rawValue: displayModeRawValue) ?? .singleContinuous }
    }

    private var selectedAppearanceMode: ReaderAppearanceMode {
        get { ReaderAppearanceMode(rawValue: appearanceModeRawValue) ?? .normal }
    }

    private var zoomPercentage: String {
        "\(Int(currentScaleFactor * 100))%"
    }

    var body: some View {
        VStack(spacing: 0) {
            readerToolbar
            Divider()

            if isSearchBarVisible {
                searchBar
            }

            HSplitView {
                if isThumbnailSidebarVisible {
                    thumbnailSidebar
                        .frame(minWidth: 140, idealWidth: 180, maxWidth: 220, maxHeight: .infinity)
                }

                pdfPane
                    .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)

                if isSidebarVisible {
                    sidebar
                        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420, maxHeight: .infinity)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(paper.title)
        .onAppear {
            syncElfEnabledState(initial: true)
            sendPDFCommand(.setDisplayMode(selectedDisplayMode))
            sendPDFCommand(.setAppearance(selectedAppearanceMode))
            loadOutline()
        }
        .onChange(of: selectionState) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if case .multiPage = newValue {
                services.showNotice("Highlights work on one page at a time for now.")
            }
        }
        .onChange(of: focusPassage?.normalizedKey) { oldValue, newValue in
            guard oldValue != newValue else { return }
            handleFocusPassageChanged()
            resolveElfPresentationIfNeeded()
        }
        .onChange(of: elfOverlayGeometry) { oldValue, newValue in
            guard oldValue != newValue else { return }
            resolveElfPresentationIfNeeded()
        }
        .onChange(of: readerElfEnabled) { oldValue, newValue in
            guard oldValue != newValue else { return }
            syncElfEnabledState(initial: false)
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue != newValue {
                flushPendingSave()
            }
        }
        .onDisappear {
            flushPendingSave()
            askAITask?.cancel()
            searchTask?.cancel()
            cancelElfWork(clearBubble: true)
            spotlightDismissTask?.cancel()
            askAISession.reset()
        }
    }

    private var readerToolbar: some View {
        HStack(spacing: 8) {
            // Left group: thumbnail sidebar, elf, annotations
            HStack(spacing: 8) {
                Button {
                    isThumbnailSidebarVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.borderless)
                .help("Toggle page thumbnails")

                Toggle(isOn: $readerElfEnabled) {
                    Label("Elf", systemImage: readerElfEnabled ? "sparkles" : "moon.zzz")
                        .font(.subheadline.weight(.medium))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                Text("\(sortedAnnotations.count) annotation\(sortedAnnotations.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Center group: zoom + page navigation
            HStack(spacing: 4) {
                Button {
                    sendPDFCommand(.zoomOut)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("-", modifiers: [.command])
                .help("Zoom out")

                Button(zoomPercentage) {
                    sendPDFCommand(.zoomToFit)
                }
                .buttonStyle(.borderless)
                .monospacedDigit()
                .font(.caption.weight(.medium))
                .help("Fit to width")

                Button {
                    sendPDFCommand(.zoomIn)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("=", modifiers: [.command])
                .help("Zoom in")

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 4)

                Button {
                    sendPDFCommand(.goToPreviousPage)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(currentPageIndex <= 0)
                .help("Previous page")

                Button {
                    isGoToPagePopoverVisible.toggle()
                    goToPageText = "\(currentPageIndex + 1)"
                } label: {
                    Text("Page \(currentPageIndex + 1) / \(totalPageCount)")
                        .monospacedDigit()
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $isGoToPagePopoverVisible) {
                    goToPagePopover
                }
                .help("Go to page")

                Button {
                    sendPDFCommand(.goToNextPage)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(currentPageIndex >= totalPageCount - 1)
                .help("Next page")
            }

            Spacer()

            // Right group: search, display, appearance, sidebar
            HStack(spacing: 8) {
                Button {
                    isSearchBarVisible.toggle()
                    if isSearchBarVisible == false {
                        clearSearch()
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("f", modifiers: [.command])
                .help("Search in document")

                Menu {
                    ForEach(ReaderDisplayMode.allCases) { mode in
                        Button {
                            displayModeRawValue = mode.rawValue
                            sendPDFCommand(.setDisplayMode(mode))
                        } label: {
                            if selectedDisplayMode == mode {
                                Label(mode.label, systemImage: "checkmark")
                            } else {
                                Text(mode.label)
                            }
                        }
                    }
                } label: {
                    Image(systemName: selectedDisplayMode.systemImage)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Display mode")

                Menu {
                    ForEach(ReaderAppearanceMode.allCases) { mode in
                        Button {
                            appearanceModeRawValue = mode.rawValue
                            sendPDFCommand(.setAppearance(mode))
                        } label: {
                            if selectedAppearanceMode == mode {
                                Label(mode.label, systemImage: "checkmark")
                            } else {
                                Text(mode.label)
                            }
                        }
                    }
                } label: {
                    Image(systemName: selectedAppearanceMode.systemImage)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Reading mode")

                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        isSidebarVisible.toggle()
                        if isSidebarVisible == false {
                            focusedField = nil
                        }
                    }
                } label: {
                    Label(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.right")
                        .font(.subheadline.weight(.medium))
                }
                .keyboardShortcut("\\", modifiers: [.command])
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search in document...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        performSearch()
                    }
                    .onChange(of: searchText) { _, newValue in
                        searchTask?.cancel()
                        searchTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            guard Task.isCancelled == false else { return }
                            performSearch()
                        }
                    }

                if searchResults.isEmpty == false {
                    Text("\(currentSearchResultIndex + 1) of \(searchResults.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Button {
                        navigateSearchResult(forward: false)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("g", modifiers: [.command, .shift])

                    Button {
                        navigateSearchResult(forward: true)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("g", modifiers: [.command])
                } else if searchText.isEmpty == false {
                    Text("No results")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    isSearchBarVisible = false
                    clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            Divider()
        }
    }

    private var goToPagePopover: some View {
        HStack(spacing: 8) {
            TextField("Page", text: $goToPageText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .onSubmit {
                    submitGoToPage()
                }

            Text("of \(totalPageCount)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Go") {
                submitGoToPage()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var thumbnailSidebar: some View {
        VStack(spacing: 0) {
            if outlineItems.isEmpty == false {
                Picker("", selection: $thumbnailSidebarTab) {
                    Text("Pages").tag(ThumbnailSidebarTab.thumbnails)
                    Text("Outline").tag(ThumbnailSidebarTab.outline)
                }
                .pickerStyle(.segmented)
                .padding(8)
            }

            if thumbnailSidebarTab == .outline, outlineItems.isEmpty == false {
                outlineView
            } else {
                ReaderThumbnailView(pdfViewReference: pdfViewReference)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var outlineView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(ReaderOutlineItem.flatten(outlineItems)) { item in
                    Button {
                        if let destination = item.destination,
                           let page = destination.page,
                           let document = pdfViewReference.pdfView?.document {
                            let pageIndex = document.index(for: page)
                            sendPDFCommand(.goToPage(pageIndex))
                        }
                    } label: {
                        Text(item.title)
                            .font(.callout)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, CGFloat(item.indentLevel) * 12)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func performSearch() {
        guard searchText.isEmpty == false else {
            clearSearch()
            return
        }
        sendPDFCommand(.search(searchText))
        currentSearchResultIndex = 0
    }

    private func navigateSearchResult(forward: Bool) {
        guard searchResults.isEmpty == false else { return }
        if forward {
            currentSearchResultIndex = (currentSearchResultIndex + 1) % searchResults.count
        } else {
            currentSearchResultIndex = (currentSearchResultIndex - 1 + searchResults.count) % searchResults.count
        }
        sendPDFCommand(.highlightSearchResult(currentSearchResultIndex))
    }

    private func clearSearch() {
        searchText = ""
        searchResults = []
        currentSearchResultIndex = 0
        sendPDFCommand(.clearSearch)
    }

    private func submitGoToPage() {
        if let pageNumber = Int(goToPageText), pageNumber >= 1, pageNumber <= totalPageCount {
            sendPDFCommand(.goToPage(pageNumber - 1))
            isGoToPagePopoverVisible = false
        }
    }

    private func loadOutline() {
        // The PDF may not be loaded yet on first appear, so retry briefly
        Task { @MainActor in
            for _ in 0..<10 {
                if let pdfView = pdfViewReference.pdfView,
                   let document = pdfView.document,
                   let outlineRoot = document.outlineRoot {
                    outlineItems = ReaderOutlineItem.extract(from: outlineRoot)
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            outlineItems = []
        }
    }

    private var pdfPane: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                ReaderPDFView(
                    url: fileURL,
                    annotations: sortedAnnotations,
                    selectionState: $selectionState,
                    focusPassage: $focusPassage,
                    overlayTargetPassage: elfOverlayTargetPassage,
                    overlayCaptureToken: elfOverlayCaptureToken,
                    overlayGeometry: $elfOverlayGeometry,
                    overlayViewportActivityAt: $elfOverlayViewportActivityAt,
                    underlinePresentation: elfUnderlinePresentation,
                    command: pdfCommand,
                    onAnnotationDoubleClick: revealAnnotation,
                    currentScaleFactor: $currentScaleFactor,
                    currentPageIndex: $currentPageIndex,
                    totalPageCount: $totalPageCount,
                    searchResults: $searchResults,
                    pdfViewReference: pdfViewReference
                )

                if let appearanceOverlayColor = selectedAppearanceMode.overlayTintColor {
                    // Multiply tint makes the PDF paper warm without washing out black text.
                    Rectangle()
                        .fill(Color(nsColor: appearanceOverlayColor))
                        .blendMode(.multiply)
                        .allowsHitTesting(false)
                }
            }
            .compositingGroup()
            .background(Color.black.opacity(0.02))

            ReaderElfPaneOverlayView(
                state: elfOverlayState,
                onTapActiveElf: dismissElfPresentation
            )

            if let selection = currentSelection {
                selectionActionBar(selection: selection)
                    .padding(18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.18), value: currentSelection != nil)
    }

    private var sidebar: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    elfSection
                    askAISection
                    annotationsSection
                    scratchpadSection
                }
                .padding(18)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .textSelection(.enabled)
            .onChange(of: sidebarRevealCommand) { _, newCommand in
                guard let newCommand else { return }
                withAnimation(.snappy(duration: 0.22)) {
                    proxy.scrollTo(newCommand.annotationID, anchor: .center)
                }
            }
        }
    }

    private func selectionActionBar(selection: ReaderSelectionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selection")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(selection.quotedText)
                .font(.subheadline)
                .lineLimit(3)

            HStack(spacing: 8) {
                ForEach(ReaderHighlightColor.allCases) { color in
                    Button {
                        lastHighlightColorRawValue = color.rawValue
                    } label: {
                        Circle()
                            .fill(Color(nsColor: color.pdfColor))
                            .frame(width: 20, height: 20)
                            .overlay {
                                if selectedHighlightColor == color {
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.85), lineWidth: 2)
                                        .padding(-3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.displayName)
                }
            }

            HStack(spacing: 10) {
                Button("Highlight") {
                    addHighlight(from: selection, openNoteEditor: false)
                }
                .keyboardShortcut("H", modifiers: [.command, .shift])

                Button("Add Note") {
                    addHighlight(from: selection, openNoteEditor: true)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])

                Button("Ask AI") {
                    beginAskAI(from: selection)
                }

                Button("Cancel", role: .cancel) {
                    sendPDFCommand(.clearSelection)
                }
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
    }

    private var elfSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Elf Companion")
                        .font(.title3.weight(.semibold))
                    Text("Autonomous critique over the passage you are reading right now.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let status = elfSession.status(now: context.date)
                    Label(status.title, systemImage: status.symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(elfStatusColor(for: status))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(elfStatusColor(for: status).opacity(0.10))
                        .clipShape(Capsule())
                }
            }

            if readerElfEnabled == false {
                Text("Turn the header toggle back on when you want the elf to watch the page again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if case let .paused(reason) = elfSession.status() {
                Text(reason.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let focusPassage {
                Text("Watching page \(focusPassage.pageNumber) via \(focusPassage.source == .selection ? "selection" : "viewport").")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Move through the PDF to give the elf a passage to watch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if elfSession.recentComments.isEmpty {
                ContentUnavailableView(
                    "No elf comments yet",
                    systemImage: "figure.fairy",
                    description: Text("Leave the elf on and dwell on a passage long enough for it to critique the paper.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(elfSession.recentComments) { comment in
                        elfCommentCard(comment)
                    }
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

    private func elfCommentCard(_ comment: ReaderElfComment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(comment.mood.displayName, systemImage: comment.mood.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(nsColor: comment.mood.accentColor))
                Spacer()
                Text(comment.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(comment.text)
                .font(.subheadline.weight(.medium))

            Text(comment.passage.quotedText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            HStack {
                Text("Page \(comment.passage.pageNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Jump") {
                    jump(to: comment.passage)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .background(Color(nsColor: comment.mood.bubbleTint))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: comment.mood.accentColor).opacity(0.18), lineWidth: 1)
        )
    }

    private var askAISection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ask AI")
                    .font(.title3.weight(.semibold))
                Spacer()
                if askAISession.exchanges.isEmpty == false {
                    Text("\(askAISession.exchanges.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                }
            }

            if let draft = askAISession.draft {
                askAIComposer(for: draft)
            } else if askAISession.exchanges.isEmpty {
                ContentUnavailableView(
                    "No Ask AI prompts yet",
                    systemImage: "sparkles",
                    description: Text("Select text in the PDF, then choose Ask AI.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                Text("Select another passage in the PDF, then choose Ask AI to ask a new question.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if askAISession.exchanges.isEmpty == false {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(askAISession.exchanges) { exchange in
                        askAIExchangeCard(exchange)
                    }
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

    private func askAIComposer(for draft: ReaderAskAIDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Page \(draft.selection.pageNumber)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if cachedDocumentContext?.documentWasTruncated == true {
                    Label("Document truncated", systemImage: "doc.text")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(draft.selection.quotedText)
                .font(.subheadline.weight(.medium))
                .lineLimit(5)

            Text("Question")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: askAIQuestionBinding)
                .focused($focusedField, equals: .askAIQuestion)
                .font(.body)
                .frame(minHeight: 110)
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )

            HStack(spacing: 10) {
                Button("Ask") {
                    submitAskAI()
                }
                .disabled(askAISession.canSubmit == false)

                Button("Clear", role: .cancel) {
                    askAISession.clearDraft()
                    if focusedField == .askAIQuestion {
                        focusedField = nil
                    }
                }
                .disabled(askAISession.isAwaitingResponse)

                Spacer()

                if askAISession.isAwaitingResponse {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private func askAIExchangeCard(_ exchange: ReaderAskAIExchange) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Page \(exchange.pageNumber)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(exchange.askedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(exchange.quotedText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Question")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(exchange.question)
                    .font(.subheadline)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Answer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ReaderMarkdownView(markdown: exchange.answer)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var annotationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Annotations")
                    .font(.title3.weight(.semibold))
                Spacer()
                if sortedAnnotations.isEmpty == false {
                    Text("\(sortedAnnotations.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                }
            }

            if sortedAnnotations.isEmpty {
                ContentUnavailableView(
                    "No highlights yet",
                    systemImage: "highlighter",
                    description: Text("Select text in the PDF, then use Highlight or Add Note.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sortedAnnotations, id: \.id) { annotation in
                        annotationRow(for: annotation)
                    }
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

    private func annotationRow(for annotation: PaperAnnotation) -> some View {
        let isExpanded = expandedAnnotationID == annotation.id
        let isSpotlighted = spotlightedAnnotationID == annotation.id
        let rowBackgroundColor = isSpotlighted
            ? Color(nsColor: annotation.color.pdfColor).opacity(0.18)
            : Color.primary.opacity(isExpanded ? 0.05 : 0.03)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color(nsColor: annotation.color.pdfColor))
                    .frame(width: 12, height: 12)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Page \(annotation.pageNumber)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()

                        Menu {
                            ForEach(ReaderHighlightColor.allCases) { color in
                                Button(color.displayName) {
                                    services.updateAnnotationColor(annotation, color: color, context: modelContext)
                                    lastHighlightColorRawValue = color.rawValue
                                }
                            }
                        } label: {
                            Image(systemName: "paintpalette")
                        }
                        .menuStyle(.borderlessButton)

                        Button {
                            sendPDFCommand(.jumpToAnnotation(annotation.id))
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                        }
                        .buttonStyle(.borderless)
                        .help("Jump to highlight")

                        Button {
                            expandAnnotation(annotation.id, focusEditor: true)
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Edit note")

                        Button(role: .destructive) {
                            services.deleteAnnotation(annotation, context: modelContext)
                            if expandedAnnotationID == annotation.id {
                                expandedAnnotationID = nil
                            }
                            if focusedField == .annotation(annotation.id) {
                                focusedField = nil
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete highlight")
                    }

                    Text(annotation.quotedText)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(isExpanded ? nil : 3)

                    if isExpanded {
                        annotationNoteContent(for: annotation)
                    } else {
                        Text(annotation.notePreviewText)
                            .font(.footnote)
                            .foregroundStyle(annotation.hasNote ? .secondary : .tertiary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(14)
        .background(rowBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if isSpotlighted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(nsColor: annotation.color.pdfColor).opacity(0.95), lineWidth: 2)
            }
        }
        .shadow(
            color: Color(nsColor: annotation.color.pdfColor).opacity(isSpotlighted ? 0.22 : 0),
            radius: isSpotlighted ? 18 : 0,
            y: isSpotlighted ? 8 : 0
        )
        .id(annotation.id)
        .animation(.snappy(duration: 0.22), value: isSpotlighted)
    }

    private var scratchpadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Scratchpad")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("General paper notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if focusedField != .scratchpad {
                    Button("Edit") {
                        focusedField = .scratchpad
                    }
                    .buttonStyle(.borderless)
                }
            }

            scratchpadContent
        }
        .padding(18)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var sortedAnnotations: [PaperAnnotation] {
        paper.annotations.sorted(by: PaperAnnotation.sidebarSort)
    }

    @ViewBuilder
    private func annotationNoteContent(for annotation: PaperAnnotation) -> some View {
        if focusedField == .annotation(annotation.id) || annotation.hasNote == false {
            ZStack(alignment: .topLeading) {
                TextEditor(text: annotationNoteBinding(for: annotation))
                    .focused($focusedField, equals: .annotation(annotation.id))
                    .font(.body)
                    .scrollContentBackground(.hidden)

                if annotation.hasNote == false {
                    Text("Add a note with markdown.")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 110)
            .padding(10)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        } else {
            ReaderMarkdownView(markdown: annotation.noteText)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var scratchpadContent: some View {
        if focusedField == .scratchpad || scratchpadIsEmpty {
            ZStack(alignment: .topLeading) {
                TextEditor(text: scratchpadBinding)
                    .focused($focusedField, equals: .scratchpad)
                    .font(.body)
                    .scrollContentBackground(.hidden)

                if scratchpadIsEmpty {
                    Text("Add paper notes with markdown.")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 220)
            .padding(10)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        } else {
            ReaderMarkdownView(markdown: paper.notes)
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                .padding(10)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
    }

    private var scratchpadIsEmpty: Bool {
        paper.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedHighlightColor: ReaderHighlightColor {
        get { ReaderHighlightColor(rawValue: lastHighlightColorRawValue) ?? .yellow }
        nonmutating set { lastHighlightColorRawValue = newValue.rawValue }
    }

    private var currentSelection: ReaderSelectionSnapshot? {
        if case let .single(snapshot) = selectionState {
            return snapshot
        }
        return nil
    }

    private var elfOverlayTargetPassage: ReaderFocusPassageSnapshot? {
        elfPresentation.targetPassage ?? focusPassage
    }

    private var elfOverlayState: ReaderElfOverlayState {
        ReaderElfOverlayState(
            status: elfSession.status(),
            presentation: elfPresentation,
            geometry: elfOverlayGeometry
        )
    }

    private var elfUnderlinePresentation: ReaderElfUnderlinePresentationState? {
        ReaderElfUnderlinePresentationState(elfPresentation)
    }

    private var scratchpadBinding: Binding<String> {
        Binding(
            get: { paper.notes },
            set: { newValue in
                paper.notes = newValue
                scheduleSave()
            }
        )
    }

    private var askAIQuestionBinding: Binding<String> {
        Binding(
            get: { askAISession.draft?.question ?? "" },
            set: { askAISession.updateQuestion($0) }
        )
    }

    private func annotationNoteBinding(for annotation: PaperAnnotation) -> Binding<String> {
        Binding(
            get: { annotation.noteText },
            set: { newValue in
                annotation.noteText = newValue
                annotation.touch()
                scheduleSave()
            }
        )
    }

    private func addHighlight(from selection: ReaderSelectionSnapshot, openNoteEditor: Bool) {
        guard let annotation = services.saveAnnotation(
            for: paper,
            selection: selection,
            color: selectedHighlightColor,
            context: modelContext
        ) else {
            return
        }

        if openNoteEditor {
            expandAnnotation(annotation.id, focusEditor: true)
            withAnimation(.snappy(duration: 0.22)) {
                isSidebarVisible = true
            }
        } else if annotation.hasNote {
            expandedAnnotationID = annotation.id
        }

        sendPDFCommand(.clearSelection)
    }

    private func beginAskAI(from selection: ReaderSelectionSnapshot) {
        askAISession.capture(selection: selection)
        withAnimation(.snappy(duration: 0.22)) {
            isSidebarVisible = true
        }
        sendPDFCommand(.clearSelection)

        DispatchQueue.main.async {
            focusedField = .askAIQuestion
        }
    }

    private func submitAskAI() {
        guard let draft = askAISession.beginRequest() else { return }

        let documentContext = resolveReaderDocumentContext()
        askAITask?.cancel()
        askAITask = Task {
            let answer = await services.answerReaderQuestion(
                draft.question,
                for: paper,
                selection: draft.selection,
                settings: settings,
                documentContext: documentContext
            )

            guard Task.isCancelled == false else { return }

            await MainActor.run {
                if let answer {
                    askAISession.finishRequest(with: draft, answer: answer)
                } else {
                    askAISession.failRequest()
                }
            }
        }
    }

    private func resolveReaderDocumentContext() -> ReaderAskAIDocumentContext {
        if let cachedDocumentContext {
            return cachedDocumentContext
        }

        let context = services.loadReaderDocumentContext(from: fileURL)
        cachedDocumentContext = context
        return context
    }

    private func syncElfEnabledState(initial: Bool) {
        if readerElfEnabled {
            elfSession.setEnabled(true)
            elfSession.clearPause()
            if initial == false {
                handleFocusPassageChanged()
            }
        } else {
            cancelElfWork(clearBubble: true)
            elfSession.setEnabled(false)
        }
    }

    private func handleFocusPassageChanged() {
        elfScheduleTask?.cancel()
        elfTask?.cancel()
        elfSession.cancelEvaluation()

        guard readerElfEnabled,
              let focusPassage,
              elfSession.pausedReason == nil else {
            return
        }

        let now = Date()
        let cooldownDelay = max(0, elfSession.cooldownUntil?.timeIntervalSince(now) ?? 0)
        let triggerDelay = max(8, cooldownDelay)

        elfScheduleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(triggerDelay * 1_000_000_000))
            guard Task.isCancelled == false else { return }
            guard self.focusPassage?.normalizedKey == focusPassage.normalizedKey else { return }
            guard elfSession.canEvaluate(focusPassage) else { return }
            startElfEvaluation(for: focusPassage)
        }
    }

    private func startElfEvaluation(for passage: ReaderFocusPassageSnapshot) {
        guard elfSession.canEvaluate(passage) else { return }

        elfSession.beginEvaluation()
        let documentContext = resolveReaderDocumentContext()
        let recentComments = elfSession.promptContextComments

        elfTask?.cancel()
        elfTask = Task {
            let result = await services.requestReaderCompanionComment(
                for: paper,
                passage: passage,
                recentComments: recentComments,
                settings: settings,
                documentContext: documentContext
            )

            guard Task.isCancelled == false else { return }

            await MainActor.run {
                switch result {
                case let .comment(output):
                    let comment = ReaderElfComment(
                        passage: passage,
                        mood: output.mood,
                        text: output.comment
                    )
                    elfSession.surface(comment)
                    surfaceElfComment(comment)
                case .noComment:
                    elfSession.finishWithoutComment(for: passage)
                case let .paused(reason):
                    elfSession.pause(reason)
                }
            }
        }
    }

    private func surfaceElfComment(_ comment: ReaderElfComment) {
        elfCaptureTask?.cancel()
        elfResolveTask?.cancel()
        elfPhaseTask?.cancel()
        elfDismissTask?.cancel()

        elfPresentation.start(comment: comment)
        elfOverlayCaptureToken = UUID()
        scheduleElfOverlayRecapture(for: comment)
        scheduleElfGeometryResolutionTimeout(for: comment)
        resolveElfPresentationIfNeeded()
    }

    private func resolveElfPresentationIfNeeded() {
        guard let comment = elfPresentation.comment else { return }

        switch elfPresentation.geometryUpdate(for: elfOverlayGeometry) {
        case .none:
            return
        case let .resolve(geometry):
            elfCaptureTask?.cancel()
            elfCaptureTask = nil
            elfResolveTask?.cancel()
            elfResolveTask = nil
            elfPresentation.resolveGeometry(geometry, commentID: comment.id)
            scheduleElfPresentation(for: comment)
        case let .refresh(geometry):
            elfPresentation.refreshLiveGeometry(geometry, commentID: comment.id)
        case .returnToDock:
            elfCaptureTask?.cancel()
            elfCaptureTask = nil
            beginElfReturn(for: comment)
        }
    }

    private func scheduleElfOverlayRecapture(for comment: ReaderElfComment) {
        let recaptureIntervals: [UInt64] = [
            80_000_000,
            80_000_000,
            100_000_000,
            120_000_000,
            140_000_000,
            160_000_000
        ]

        elfCaptureTask = Task { @MainActor in
            for interval in recaptureIntervals {
                try? await Task.sleep(nanoseconds: interval)
                guard Task.isCancelled == false else { return }
                guard elfPresentation.token == comment.id else { return }
                guard case .awaitingGeometry = elfPresentation.targetResolution else { return }

                elfOverlayCaptureToken = UUID()
            }

            elfCaptureTask = nil
        }
    }

    private func scheduleElfGeometryResolutionTimeout(for comment: ReaderElfComment) {
        elfResolveTask?.cancel()
        let startedAt = Date.now
        elfResolveTask = Task { @MainActor in
            while let waitInterval = ReaderElfPresentationState.geometryResolutionWaitInterval(
                startedAt: startedAt,
                lastViewportActivityAt: elfOverlayViewportActivityAt
            ) {
                try? await Task.sleep(nanoseconds: UInt64(waitInterval * 1_000_000_000))
                guard Task.isCancelled == false else { return }
                guard elfPresentation.token == comment.id else { return }
                guard case .awaitingGeometry = elfPresentation.targetResolution else {
                    elfResolveTask = nil
                    return
                }
            }

            guard Task.isCancelled == false else { return }
            guard elfPresentation.token == comment.id else { return }
            guard case .awaitingGeometry = elfPresentation.targetResolution else {
                elfResolveTask = nil
                return
            }

            elfSession.dismissActiveComment()
            elfPresentation.dock(commentID: comment.id)
            elfResolveTask = nil
        }
    }

    private func scheduleElfPresentation(for comment: ReaderElfComment) {
        elfPhaseTask?.cancel()
        elfDismissTask?.cancel()

        elfPhaseTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(ReaderElfPresentationState.jumpLiftDuration * 1_000_000_000)
            )
            guard Task.isCancelled == false else { return }
            guard elfPresentation.token == comment.id else { return }
            elfPresentation.beginPresenting(commentID: comment.id)
        }
    }

    private func beginElfReturn(for comment: ReaderElfComment) {
        guard elfPresentation.token == comment.id else { return }
        guard elfPresentation.phase == .jumpingIn || elfPresentation.phase == .presenting else { return }

        elfPhaseTask?.cancel()
        elfDismissTask?.cancel()
        elfPresentation.beginReturning(commentID: comment.id)
        elfSession.dismissActiveComment()

        elfDismissTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(ReaderElfPresentationState.returnDuration * 1_000_000_000)
            )
            guard Task.isCancelled == false else { return }
            guard elfPresentation.token == comment.id else { return }
            elfPresentation.dock(commentID: comment.id)
        }
    }

    private func dismissElfPresentation() {
        guard let comment = elfPresentation.comment else { return }
        beginElfReturn(for: comment)
    }

    private func cancelElfWork(clearBubble: Bool) {
        elfScheduleTask?.cancel()
        elfTask?.cancel()
        elfCaptureTask?.cancel()
        elfResolveTask?.cancel()
        elfPhaseTask?.cancel()
        elfDismissTask?.cancel()
        elfScheduleTask = nil
        elfTask = nil
        elfCaptureTask = nil
        elfResolveTask = nil
        elfPhaseTask = nil
        elfDismissTask = nil
        elfSession.cancelEvaluation()
        if clearBubble {
            elfSession.dismissActiveComment()
            elfPresentation.dock(at: .now)
        }
    }

    private func expandAnnotation(_ annotationID: UUID, focusEditor: Bool) {
        withAnimation(.snappy(duration: 0.18)) {
            expandedAnnotationID = annotationID
            isSidebarVisible = true
        }

        guard focusEditor else { return }
        DispatchQueue.main.async {
            focusedField = .annotation(annotationID)
        }
    }

    private func revealAnnotation(_ annotationID: UUID) {
        guard paper.annotations.contains(where: { $0.id == annotationID }) else {
            return
        }

        withAnimation(.snappy(duration: 0.18)) {
            isSidebarVisible = true
        }
        sendPDFCommand(.clearSelection)

        DispatchQueue.main.async {
            sidebarRevealCommand = ReaderSidebarRevealCommand(annotationID: annotationID)
            spotlightAnnotation(annotationID)
        }
    }

    private func jump(to passage: ReaderFocusPassageSnapshot) {
        sendPDFCommand(.jumpToPassage(passage.jumpTarget))
    }

    private func spotlightAnnotation(_ annotationID: UUID) {
        spotlightDismissTask?.cancel()
        withAnimation(.snappy(duration: 0.18)) {
            spotlightedAnnotationID = annotationID
        }

        spotlightDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard Task.isCancelled == false else { return }
            guard spotlightedAnnotationID == annotationID else { return }

            withAnimation(.snappy(duration: 0.18)) {
                spotlightedAnnotationID = nil
            }
        }
    }

    private func sendPDFCommand(_ kind: ReaderPDFCommandKind) {
        pdfCommand = ReaderPDFCommand(kind: kind)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard Task.isCancelled == false else { return }
            services.persistNotes(context: modelContext)
        }
    }

    private func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        services.persistNotes(context: modelContext)
    }

    private func elfStatusColor(for status: ReaderElfStatus) -> Color {
        switch status {
        case .off:
            return .secondary
        case .listening:
            return .orange
        case .thinking:
            return .mint
        case .coolingDown:
            return .blue
        case .paused:
            return .red
        }
    }
}

@MainActor
private final class ReaderElfUnderlineOverlayProvider: NSObject, @preconcurrency PDFPageOverlayViewProvider {
    private var presentation: ReaderElfUnderlinePresentationState?
    private var displayBox: PDFDisplayBox = .cropBox
    private var overlayViews: [ObjectIdentifier: ReaderElfUnderlineOverlayView] = [:]

    func update(
        presentation newPresentation: ReaderElfUnderlinePresentationState?,
        displayBox: PDFDisplayBox,
        pdfView: PDFView
    ) {
        self.presentation = newPresentation
        self.displayBox = displayBox

        for overlayView in overlayViews.values {
            overlayView.update(
                displayBox: displayBox,
                presentation: presentationForPage(overlayView.page)
            )
        }
    }

    func reset() {
        for overlayView in overlayViews.values {
            overlayView.update(displayBox: displayBox, presentation: nil)
        }
        overlayViews.removeAll()
        presentation = nil
    }

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> NSView? {
        let overlayView = ReaderElfUnderlineOverlayView(
            page: page,
            displayBox: view.displayBox,
            presentation: presentationForPage(page)
        )
        overlayViews[ObjectIdentifier(page)] = overlayView
        return overlayView
    }

    func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: NSView, for page: PDFPage) {
        guard let overlayView = overlayView as? ReaderElfUnderlineOverlayView else { return }
        overlayViews[ObjectIdentifier(page)] = overlayView
        overlayView.update(
            displayBox: pdfView.displayBox,
            presentation: presentationForPage(page)
        )
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: NSView, for page: PDFPage) {
        overlayViews.removeValue(forKey: ObjectIdentifier(page))
        (overlayView as? ReaderElfUnderlineOverlayView)?.update(displayBox: pdfView.displayBox, presentation: nil)
    }

    private func presentationForPage(_ page: PDFPage?) -> ReaderElfUnderlinePresentationState? {
        guard let page,
              let presentation,
              let document = page.document,
              document.index(for: page) == presentation.pageIndex else {
            return nil
        }
        return presentation
    }
}

@MainActor
private final class ReaderElfUnderlineOverlayView: NSView {
    private(set) weak var page: PDFPage?
    private var displayBox: PDFDisplayBox
    private var presentation: ReaderElfUnderlinePresentationState?
    private var displayTimer: Timer?

    override var isOpaque: Bool {
        false
    }

    init(
        page: PDFPage,
        displayBox: PDFDisplayBox,
        presentation: ReaderElfUnderlinePresentationState?
    ) {
        self.page = page
        self.displayBox = displayBox
        self.presentation = presentation
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        restartDisplayTimerIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let page,
              let presentation,
              let document = page.document,
              document.index(for: page) == presentation.pageIndex,
              bounds.isEmpty == false else {
            return
        }

        let snapshot = ReaderElfUnderlineTimeline.snapshot(for: presentation, at: .now)
        guard snapshot.opacity > 0.01, snapshot.segments.isEmpty == false else {
            return
        }

        let pageBounds = page.bounds(for: displayBox).standardized
        guard pageBounds.width > 0.01, pageBounds.height > 0.01 else {
            return
        }

        let xScale = bounds.width / pageBounds.width
        let yScale = bounds.height / pageBounds.height
        let strokeColor = underlineColor(for: presentation.mood).withAlphaComponent(snapshot.opacity)
        let glowColor = underlineColor(for: presentation.mood).withAlphaComponent(snapshot.opacity * 0.28)

        for segment in snapshot.segments {
            let frame = convertedFrame(
                for: segment.frame,
                pageBounds: pageBounds,
                xScale: xScale,
                yScale: yScale
            )
            guard frame.width > 0.5, frame.height > 0.5 else { continue }

            let endPoint = CGPoint(
                x: frame.minX + (frame.width * max(0, min(1, segment.progress))),
                y: frame.midY
            )

            let glowPath = NSBezierPath()
            glowPath.lineCapStyle = .round
            glowPath.lineJoinStyle = .round
            glowPath.lineWidth = max(3.4, frame.height + 1.4)
            glowPath.move(to: CGPoint(x: frame.minX, y: frame.midY))
            glowPath.line(to: endPoint)
            glowColor.setStroke()
            glowPath.stroke()

            let path = NSBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.lineWidth = max(2, frame.height)
            path.move(to: CGPoint(x: frame.minX, y: frame.midY))
            path.line(to: endPoint)
            strokeColor.setStroke()
            path.stroke()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            displayTimer?.invalidate()
            displayTimer = nil
        }
        restartDisplayTimerIfNeeded()
    }

    func update(
        displayBox: PDFDisplayBox,
        presentation: ReaderElfUnderlinePresentationState?
    ) {
        self.displayBox = displayBox
        self.presentation = presentation
        restartDisplayTimerIfNeeded()
        needsDisplay = true
    }

    private func restartDisplayTimerIfNeeded() {
        displayTimer?.invalidate()
        displayTimer = nil

        guard window != nil,
              let presentation,
              presentation.phase != .docked else {
            return
        }

        let timer = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.needsDisplay = true
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func convertedFrame(
        for underlineFrame: CGRect,
        pageBounds: CGRect,
        xScale: CGFloat,
        yScale: CGFloat
    ) -> CGRect {
        CGRect(
            x: (underlineFrame.minX - pageBounds.minX) * xScale,
            y: (underlineFrame.minY - pageBounds.minY) * yScale,
            width: underlineFrame.width * xScale,
            height: max(2, underlineFrame.height * yScale)
        ).standardized
    }

    private func underlineColor(for mood: ReaderElfMood) -> NSColor {
        switch mood {
        case .skeptical, .alarmed:
            return .systemRed
        case .amused, .intrigued:
            return .systemRed.withAlphaComponent(0.92)
        }
    }
}

private enum ReaderFocusField: Hashable {
    case scratchpad
    case annotation(UUID)
    case askAIQuestion
}

private enum ReaderPDFSelectionState: Equatable {
    case none
    case single(ReaderSelectionSnapshot)
    case multiPage
}

private struct ReaderPDFCommand: Equatable {
    let id = UUID()
    let kind: ReaderPDFCommandKind
}

private struct ReaderSidebarRevealCommand: Equatable {
    let id = UUID()
    let annotationID: UUID
}

private enum ReaderPDFCommandKind: Equatable {
    case clearSelection
    case jumpToAnnotation(UUID)
    case jumpToPassage(ReaderPassageJumpTarget)
    case zoomIn
    case zoomOut
    case zoomToFit
    case goToPage(Int)
    case goToNextPage
    case goToPreviousPage
    case setDisplayMode(ReaderDisplayMode)
    case setAppearance(ReaderAppearanceMode)
    case search(String)
    case highlightSearchResult(Int)
    case clearSearch
}

enum ReaderDisplayMode: String, CaseIterable, Identifiable {
    case singlePage
    case singleContinuous
    case twoPage
    case twoPageContinuous

    var id: String { rawValue }

    var label: String {
        switch self {
        case .singlePage: return "Single Page"
        case .singleContinuous: return "Continuous"
        case .twoPage: return "Two Pages"
        case .twoPageContinuous: return "Two-Up Continuous"
        }
    }

    var systemImage: String {
        switch self {
        case .singlePage: return "doc"
        case .singleContinuous: return "doc.text"
        case .twoPage: return "book"
        case .twoPageContinuous: return "book.pages"
        }
    }

    var pdfDisplayMode: PDFDisplayMode {
        switch self {
        case .singlePage: return .singlePage
        case .singleContinuous: return .singlePageContinuous
        case .twoPage: return .twoUp
        case .twoPageContinuous: return .twoUpContinuous
        }
    }
}

enum ReaderAppearanceMode: String, CaseIterable, Identifiable {
    case normal
    case sepia
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .sepia: return "Sepia"
        case .dark: return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .normal: return "sun.max"
        case .sepia: return "sun.dust"
        case .dark: return "moon"
        }
    }

    var pdfBackgroundColor: NSColor {
        switch self {
        case .normal:
            return .windowBackgroundColor
        case .sepia:
            return NSColor(red: 0.96, green: 0.92, blue: 0.84, alpha: 1.0)
        case .dark:
            return NSColor(white: 0.15, alpha: 1.0)
        }
    }

    var overlayTintColor: NSColor? {
        switch self {
        case .sepia:
            return NSColor(red: 0.94, green: 0.87, blue: 0.72, alpha: 0.78)
        case .normal, .dark:
            return nil
        }
    }
}

private struct ReaderOutlineItem: Identifiable {
    let id = UUID()
    let title: String
    let destination: PDFDestination?
    let indentLevel: Int
    let children: [ReaderOutlineItem]

    static func extract(from outline: PDFOutline?, level: Int = 0) -> [ReaderOutlineItem] {
        guard let outline else { return [] }
        var items: [ReaderOutlineItem] = []
        for i in 0..<outline.numberOfChildren {
            guard let child = outline.child(at: i) else { continue }
            let childItems = extract(from: child, level: level + 1)
            items.append(ReaderOutlineItem(
                title: child.label ?? "Untitled",
                destination: child.destination,
                indentLevel: level,
                children: childItems
            ))
        }
        return items
    }

    static func flatten(_ items: [ReaderOutlineItem]) -> [ReaderOutlineItem] {
        var result: [ReaderOutlineItem] = []
        for item in items {
            result.append(item)
            result.append(contentsOf: flatten(item.children))
        }
        return result
    }
}

private enum ThumbnailSidebarTab: String, CaseIterable {
    case thumbnails
    case outline
}

@MainActor
final class PDFViewReference: ObservableObject {
    weak var pdfView: PDFView?
}

private struct ReaderPDFView: NSViewRepresentable {
    let url: URL
    let annotations: [PaperAnnotation]
    @Binding var selectionState: ReaderPDFSelectionState
    @Binding var focusPassage: ReaderFocusPassageSnapshot?
    let overlayTargetPassage: ReaderFocusPassageSnapshot?
    let overlayCaptureToken: UUID
    @Binding var overlayGeometry: ReaderElfGeometrySnapshot?
    @Binding var overlayViewportActivityAt: Date?
    let underlinePresentation: ReaderElfUnderlinePresentationState?
    let command: ReaderPDFCommand?
    let onAnnotationDoubleClick: (UUID) -> Void
    @Binding var currentScaleFactor: CGFloat
    @Binding var currentPageIndex: Int
    @Binding var totalPageCount: Int
    @Binding var searchResults: [PDFSelection]
    let pdfViewReference: PDFViewReference

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectionBinding: $selectionState,
            focusPassageBinding: $focusPassage,
            overlayGeometryBinding: $overlayGeometry,
            overlayViewportActivityBinding: $overlayViewportActivityAt,
            overlayTargetPassage: overlayTargetPassage,
            overlayCaptureToken: overlayCaptureToken,
            underlinePresentation: underlinePresentation,
            onAnnotationDoubleClick: onAnnotationDoubleClick,
            scaleFactorBinding: $currentScaleFactor,
            pageIndexBinding: $currentPageIndex,
            pageCountBinding: $totalPageCount,
            searchResultsBinding: $searchResults
        )
    }

    func makeNSView(context: Context) -> InteractivePDFView {
        let view = InteractivePDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = .windowBackgroundColor
        view.annotationDoubleClickHandler = { annotationID in
            context.coordinator.handleAnnotationDoubleClick(annotationID)
        }
        context.coordinator.configure(pdfView: view)
        context.coordinator.loadDocumentIfNeeded(from: url, into: view)
        context.coordinator.reconcileAnnotations(annotations, in: view)
        context.coordinator.updateOverlayGeometry(in: view)
        pdfViewReference.pdfView = view
        return view
    }

    func updateNSView(_ nsView: InteractivePDFView, context: Context) {
        context.coordinator.configure(pdfView: nsView)
        context.coordinator.selectionBinding = $selectionState
        context.coordinator.focusPassageBinding = $focusPassage
        context.coordinator.overlayGeometryBinding = $overlayGeometry
        context.coordinator.overlayViewportActivityBinding = $overlayViewportActivityAt
        context.coordinator.overlayTargetPassage = overlayTargetPassage
        context.coordinator.overlayCaptureToken = overlayCaptureToken
        context.coordinator.underlinePresentation = underlinePresentation
        context.coordinator.onAnnotationDoubleClick = onAnnotationDoubleClick
        context.coordinator.scaleFactorBinding = $currentScaleFactor
        context.coordinator.pageIndexBinding = $currentPageIndex
        context.coordinator.pageCountBinding = $totalPageCount
        context.coordinator.searchResultsBinding = $searchResults
        nsView.annotationDoubleClickHandler = { annotationID in
            context.coordinator.handleAnnotationDoubleClick(annotationID)
        }
        context.coordinator.loadDocumentIfNeeded(from: url, into: nsView)
        context.coordinator.reconcileAnnotations(annotations, in: nsView)
        context.coordinator.updateUnderlinePresentation(in: nsView)
        context.coordinator.updateOverlayGeometry(in: nsView)
        context.coordinator.apply(command: command, annotations: annotations, in: nsView)
        pdfViewReference.pdfView = nsView
    }

    final class InteractivePDFView: PDFView {
        var annotationDoubleClickHandler: ((UUID) -> Void)?

        override func mouseDown(with event: NSEvent) {
            guard event.clickCount == 2,
                  let annotationID = annotationIDForDoubleClick(event) else {
                super.mouseDown(with: event)
                return
            }

            annotationDoubleClickHandler?(annotationID)
        }

        private func annotationIDForDoubleClick(_ event: NSEvent) -> UUID? {
            let pointInView = convert(event.locationInWindow, from: nil)
            guard let page = page(for: pointInView, nearest: false) else {
                return nil
            }

            let pointOnPage = convert(pointInView, to: page)
            guard let annotation = page.annotation(at: pointOnPage),
                  let overlayIdentity = ReaderHighlightOverlayIdentity(userName: annotation.userName) else {
                return nil
            }

            return overlayIdentity.annotationID
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var selectionBinding: Binding<ReaderPDFSelectionState>
        var focusPassageBinding: Binding<ReaderFocusPassageSnapshot?>
        var overlayGeometryBinding: Binding<ReaderElfGeometrySnapshot?>
        var overlayViewportActivityBinding: Binding<Date?>
        var overlayTargetPassage: ReaderFocusPassageSnapshot?
        var overlayCaptureToken: UUID
        var underlinePresentation: ReaderElfUnderlinePresentationState?
        var onAnnotationDoubleClick: (UUID) -> Void
        var scaleFactorBinding: Binding<CGFloat>
        var pageIndexBinding: Binding<Int>
        var pageCountBinding: Binding<Int>
        var searchResultsBinding: Binding<[PDFSelection]>
        private weak var observedPDFView: PDFView?
        private weak var observedViewportClipView: NSClipView?
        private var loadedURL: URL?
        private var handledCommandID: UUID?
        private var lastOverlayViewportActivityAt: Date?
        private let underlineOverlayProvider = ReaderElfUnderlineOverlayProvider()

        init(
            selectionBinding: Binding<ReaderPDFSelectionState>,
            focusPassageBinding: Binding<ReaderFocusPassageSnapshot?>,
            overlayGeometryBinding: Binding<ReaderElfGeometrySnapshot?>,
            overlayViewportActivityBinding: Binding<Date?>,
            overlayTargetPassage: ReaderFocusPassageSnapshot?,
            overlayCaptureToken: UUID,
            underlinePresentation: ReaderElfUnderlinePresentationState?,
            onAnnotationDoubleClick: @escaping (UUID) -> Void,
            scaleFactorBinding: Binding<CGFloat>,
            pageIndexBinding: Binding<Int>,
            pageCountBinding: Binding<Int>,
            searchResultsBinding: Binding<[PDFSelection]>
        ) {
            self.selectionBinding = selectionBinding
            self.focusPassageBinding = focusPassageBinding
            self.overlayGeometryBinding = overlayGeometryBinding
            self.overlayViewportActivityBinding = overlayViewportActivityBinding
            self.overlayTargetPassage = overlayTargetPassage
            self.overlayCaptureToken = overlayCaptureToken
            self.underlinePresentation = underlinePresentation
            self.onAnnotationDoubleClick = onAnnotationDoubleClick
            self.scaleFactorBinding = scaleFactorBinding
            self.pageIndexBinding = pageIndexBinding
            self.pageCountBinding = pageCountBinding
            self.searchResultsBinding = searchResultsBinding
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func configure(pdfView: PDFView) {
            if observedPDFView !== pdfView {
                NotificationCenter.default.removeObserver(self)
                observedPDFView = pdfView
                pdfView.pageOverlayViewProvider = underlineOverlayProvider
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleSelectionChanged(_:)),
                    name: Notification.Name.PDFViewSelectionChanged,
                    object: pdfView
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleVisiblePagesChanged(_:)),
                    name: Notification.Name.PDFViewVisiblePagesChanged,
                    object: pdfView
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleScaleChanged(_:)),
                    name: Notification.Name.PDFViewScaleChanged,
                    object: pdfView
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handlePageChanged(_:)),
                    name: Notification.Name.PDFViewPageChanged,
                    object: pdfView
                )
            }

            observeViewportClipViewIfNeeded(in: pdfView)
        }

        func loadDocumentIfNeeded(from url: URL, into pdfView: PDFView) {
            guard loadedURL != url else { return }
            pdfView.document = PDFDocument(url: url)
            loadedURL = url
            handledCommandID = nil
            selectionBinding.wrappedValue = .none
            focusPassageBinding.wrappedValue = ReaderFocusPassageExtractor.passage(in: pdfView)
            underlineOverlayProvider.reset()
            pageCountBinding.wrappedValue = pdfView.document?.pageCount ?? 0
            scaleFactorBinding.wrappedValue = pdfView.scaleFactor
            syncCurrentPageIndex(in: pdfView)
            updateUnderlinePresentation(in: pdfView)
            updateOverlayGeometry(in: pdfView)
        }

        func reconcileAnnotations(_ annotations: [PaperAnnotation], in pdfView: PDFView) {
            guard let document = pdfView.document else { return }

            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                for annotation in page.annotations where ReaderHighlightOverlayIdentity(userName: annotation.userName) != nil {
                    page.removeAnnotation(annotation)
                }
            }

            for annotation in annotations {
                guard let page = document.page(at: annotation.pageIndex) else { continue }
                for (rectIndex, rect) in annotation.rects.enumerated() {
                    let overlay = PDFAnnotation(bounds: rect.cgRect, forType: .highlight, withProperties: nil)
                    overlay.color = annotation.color.pdfColor
                    overlay.userName = annotation.overlayIdentity(forRectAt: rectIndex).userName
                    page.addAnnotation(overlay)
                }
            }
        }

        func updateOverlayGeometry(in pdfView: PDFView) {
            overlayGeometryBinding.wrappedValue = ReaderElfGeometrySnapshot.capture(
                for: overlayTargetPassage ?? focusPassageBinding.wrappedValue,
                in: pdfView
            )
        }

        func updateUnderlinePresentation(in pdfView: PDFView) {
            underlineOverlayProvider.update(
                presentation: underlinePresentation,
                displayBox: pdfView.displayBox,
                pdfView: pdfView
            )
        }

        func handleAnnotationDoubleClick(_ annotationID: UUID) {
            onAnnotationDoubleClick(annotationID)
        }

        func apply(command: ReaderPDFCommand?, annotations: [PaperAnnotation], in pdfView: PDFView) {
            guard let command, handledCommandID != command.id else { return }
            handledCommandID = command.id

            switch command.kind {
            case .clearSelection:
                pdfView.clearSelection()
                selectionBinding.wrappedValue = .none
                updateFocusPassage(in: pdfView)
            case let .jumpToAnnotation(annotationID):
                jump(to: annotationID, annotations: annotations, in: pdfView)
            case let .jumpToPassage(target):
                jump(to: target, in: pdfView)
            case .zoomIn:
                pdfView.autoScales = false
                pdfView.scaleFactor = min(pdfView.scaleFactor * 1.25, 8.0)
            case .zoomOut:
                pdfView.autoScales = false
                pdfView.scaleFactor = max(pdfView.scaleFactor / 1.25, 0.1)
            case .zoomToFit:
                pdfView.autoScales = true
            case let .goToPage(pageIndex):
                if let page = pdfView.document?.page(at: pageIndex) {
                    pdfView.go(to: page)
                }
            case .goToNextPage:
                pdfView.goToNextPage(nil)
            case .goToPreviousPage:
                pdfView.goToPreviousPage(nil)
            case let .setDisplayMode(mode):
                pdfView.displayMode = mode.pdfDisplayMode
            case let .setAppearance(mode):
                applyAppearance(mode, to: pdfView)
            case let .search(text):
                performSearch(text, in: pdfView)
            case let .highlightSearchResult(index):
                highlightSearchResult(at: index, in: pdfView)
            case .clearSearch:
                pdfView.highlightedSelections = nil
                searchResultsBinding.wrappedValue = []
            }
        }

        private func applyAppearance(_ mode: ReaderAppearanceMode, to pdfView: PDFView) {
            pdfView.wantsLayer = true
            pdfView.layer?.filters = nil
            pdfView.layer?.backgroundFilters = nil
            pdfView.backgroundColor = mode.pdfBackgroundColor

            switch mode {
            case .normal, .sepia:
                break
            case .dark:
                if let invertFilter = CIFilter(name: "CIColorInvert") {
                    pdfView.layer?.filters = [invertFilter]
                }
            }
        }

        private func performSearch(_ text: String, in pdfView: PDFView) {
            guard let document = pdfView.document, text.isEmpty == false else {
                pdfView.highlightedSelections = nil
                searchResultsBinding.wrappedValue = []
                return
            }
            let results = document.findString(text, withOptions: [.caseInsensitive])
            searchResultsBinding.wrappedValue = results
            pdfView.highlightedSelections = results
            if let first = results.first {
                pdfView.setCurrentSelection(first, animate: true)
                pdfView.scrollSelectionToVisible(nil)
            }
        }

        private func highlightSearchResult(at index: Int, in pdfView: PDFView) {
            let results = searchResultsBinding.wrappedValue
            guard index >= 0, index < results.count else { return }
            pdfView.setCurrentSelection(results[index], animate: true)
            pdfView.scrollSelectionToVisible(nil)
        }

        private func syncCurrentPageIndex(in pdfView: PDFView) {
            guard let currentPage = pdfView.currentPage,
                  let document = pdfView.document else { return }
            pageIndexBinding.wrappedValue = document.index(for: currentPage)
        }

        private func jump(to annotationID: UUID, annotations: [PaperAnnotation], in pdfView: PDFView) {
            guard let annotation = annotations.first(where: { $0.id == annotationID }) else {
                return
            }

            jump(to: annotation.jumpTarget, in: pdfView)
        }

        private func jump(to target: ReaderPassageJumpTarget, in pdfView: PDFView) {
            guard let page = pdfView.document?.page(at: target.pageIndex) else {
                return
            }

            pdfView.go(to: target.scrollRect, on: page)
            updateFocusPassage(in: pdfView)
        }

        private func updateFocusPassage(in pdfView: PDFView) {
            let selectionState = selectionState(for: pdfView)
            selectionBinding.wrappedValue = selectionState

            switch selectionState {
            case let .single(snapshot):
                focusPassageBinding.wrappedValue = ReaderFocusPassageExtractor.passage(from: snapshot)
            case .none, .multiPage:
                focusPassageBinding.wrappedValue = ReaderFocusPassageExtractor.passage(in: pdfView)
            }
            overlayGeometryBinding.wrappedValue = ReaderElfGeometrySnapshot.capture(
                for: overlayTargetPassage ?? focusPassageBinding.wrappedValue,
                in: pdfView
            )
            updateUnderlinePresentation(in: pdfView)
        }

        private func observeViewportClipViewIfNeeded(in pdfView: PDFView) {
            let viewportClipView = pdfView.subviews
                .compactMap { $0 as? NSScrollView }
                .first?
                .contentView

            guard observedViewportClipView !== viewportClipView else {
                return
            }

            if let observedViewportClipView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedViewportClipView
                )
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.frameDidChangeNotification,
                    object: observedViewportClipView
                )
            }

            observedViewportClipView = viewportClipView

            guard let viewportClipView else {
                return
            }

            viewportClipView.postsBoundsChangedNotifications = true
            viewportClipView.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleViewportBoundsChanged(_:)),
                name: NSView.boundsDidChangeNotification,
                object: viewportClipView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleViewportFrameChanged(_:)),
                name: NSView.frameDidChangeNotification,
                object: viewportClipView
            )
        }

        private func recordOverlayViewportActivity(at date: Date = .now) {
            if let lastOverlayViewportActivityAt,
               date.timeIntervalSince(lastOverlayViewportActivityAt) < 0.05 {
                return
            }

            lastOverlayViewportActivityAt = date
            overlayViewportActivityBinding.wrappedValue = date
        }

        private func handleViewportChanged(in pdfView: PDFView) {
            recordOverlayViewportActivity()

            if case .single = selectionBinding.wrappedValue {
                updateUnderlinePresentation(in: pdfView)
                updateOverlayGeometry(in: pdfView)
                return
            }

            focusPassageBinding.wrappedValue = ReaderFocusPassageExtractor.passage(in: pdfView)
            updateUnderlinePresentation(in: pdfView)
            updateOverlayGeometry(in: pdfView)
        }

        private func selectionState(for pdfView: PDFView) -> ReaderPDFSelectionState {
            guard let selection = pdfView.currentSelection,
                  let document = pdfView.document else {
                return .none
            }

            let pageIndexes = Set(
                selection.pages
                    .map { document.index(for: $0) }
                    .filter { $0 >= 0 && $0 < document.pageCount }
            )

            guard pageIndexes.isEmpty == false else {
                return .none
            }

            guard pageIndexes.count == 1, let pageIndex = pageIndexes.first else {
                return .multiPage
            }

            guard let page = document.page(at: pageIndex) else {
                return .none
            }

            let lineSelections = selection.selectionsByLine()
                .filter { lineSelection in
                    lineSelection.pages.contains(where: { document.index(for: $0) == pageIndex })
                }
            let rects = lineSelections.isEmpty
                ? [selection.bounds(for: page).standardized]
                : lineSelections.map { $0.bounds(for: page).standardized }

            guard let snapshot = ReaderSelectionSnapshot(
                pageIndex: pageIndex,
                quotedText: selection.string ?? "",
                rects: rects
            ) else {
                return .none
            }

            return .single(snapshot)
        }

        @objc
        private func handleSelectionChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else {
                selectionBinding.wrappedValue = .none
                focusPassageBinding.wrappedValue = nil
                overlayGeometryBinding.wrappedValue = nil
                return
            }

            updateFocusPassage(in: pdfView)
        }

        @objc
        private func handleVisiblePagesChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else {
                return
            }

            handleViewportChanged(in: pdfView)
        }

        @objc
        private func handleViewportBoundsChanged(_ notification: Notification) {
            guard notification.object as? NSClipView === observedViewportClipView,
                  let pdfView = observedPDFView else {
                return
            }

            handleViewportChanged(in: pdfView)
        }

        @objc
        private func handleViewportFrameChanged(_ notification: Notification) {
            guard notification.object as? NSClipView === observedViewportClipView,
                  let pdfView = observedPDFView else {
                return
            }

            handleViewportChanged(in: pdfView)
        }

        @objc
        private func handleScaleChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else { return }
            scaleFactorBinding.wrappedValue = pdfView.scaleFactor
        }

        @objc
        private func handlePageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else { return }
            syncCurrentPageIndex(in: pdfView)
        }
    }
}

private struct ReaderThumbnailView: NSViewRepresentable {
    let pdfViewReference: PDFViewReference

    func makeNSView(context: Context) -> PDFThumbnailView {
        let thumbnailView = PDFThumbnailView()
        thumbnailView.thumbnailSize = CGSize(width: 120, height: 160)
        thumbnailView.backgroundColor = .controlBackgroundColor
        if let pdfView = pdfViewReference.pdfView {
            thumbnailView.pdfView = pdfView
        }
        return thumbnailView
    }

    func updateNSView(_ nsView: PDFThumbnailView, context: Context) {
        if nsView.pdfView !== pdfViewReference.pdfView {
            nsView.pdfView = pdfViewReference.pdfView
        }
    }
}
