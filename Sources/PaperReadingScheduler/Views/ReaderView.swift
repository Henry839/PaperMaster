import PDFKit
import SwiftData
import SwiftUI

struct ReaderView: View {
    @AppStorage("reader.lastHighlightColor") private var lastHighlightColorRawValue = ReaderHighlightColor.yellow.rawValue
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @Bindable var paper: Paper
    let fileURL: URL
    let settings: UserSettings

    @FocusState private var focusedField: ReaderFocusField?
    @State private var selectionState: ReaderPDFSelectionState = .none
    @State private var isSidebarVisible = true
    @State private var expandedAnnotationID: UUID?
    @State private var pdfCommand: ReaderPDFCommand?
    @State private var askAISession = ReaderAskAISessionState()
    @State private var cachedDocumentContext: ReaderAskAIDocumentContext?
    @State private var askAITask: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            HSplitView {
                pdfPane
                    .frame(minWidth: 760, maxWidth: .infinity, maxHeight: .infinity)

                if isSidebarVisible {
                    sidebar
                        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420, maxHeight: .infinity)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(minWidth: 1_120, minHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(paper.title)
        .onChange(of: selectionState) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if case .multiPage = newValue {
                services.showNotice("Highlights work on one page at a time for now.")
            }
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue != newValue {
                flushPendingSave()
            }
        }
        .onDisappear {
            flushPendingSave()
            askAITask?.cancel()
            askAISession.reset()
        }
    }

    private var headerBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(paper.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(sortedAnnotations.count) annotation\(sortedAnnotations.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar", systemImage: isSidebarVisible ? "sidebar.right" : "sidebar.right") {
                withAnimation(.snappy(duration: 0.22)) {
                    isSidebarVisible.toggle()
                    if isSidebarVisible == false {
                        focusedField = nil
                    }
                }
            }
            .keyboardShortcut("\\", modifiers: [.command])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var pdfPane: some View {
        ZStack(alignment: .topTrailing) {
            ReaderPDFView(
                url: fileURL,
                annotations: sortedAnnotations,
                selectionState: $selectionState,
                command: pdfCommand
            )
            .background(Color.black.opacity(0.02))

            if let selection = currentSelection {
                selectionActionBar(selection: selection)
                    .padding(18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.18), value: currentSelection != nil)
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                askAISection
                annotationsSection
                scratchpadSection
            }
            .padding(18)
        }
        .background(Color(nsColor: .controlBackgroundColor))
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
                Text(exchange.answer)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
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
                        TextEditor(text: annotationNoteBinding(for: annotation))
                            .focused($focusedField, equals: .annotation(annotation.id))
                            .font(.body)
                            .frame(minHeight: 110)
                            .padding(10)
                            .background(Color.primary.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                            )
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
        .background(Color.primary.opacity(isExpanded ? 0.05 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            }

            TextEditor(text: scratchpadBinding)
                .focused($focusedField, equals: .scratchpad)
                .font(.body)
                .frame(minHeight: 220)
                .padding(10)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
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

private enum ReaderPDFCommandKind: Equatable {
    case clearSelection
    case jumpToAnnotation(UUID)
}

private struct ReaderPDFView: NSViewRepresentable {
    let url: URL
    let annotations: [PaperAnnotation]
    @Binding var selectionState: ReaderPDFSelectionState
    let command: ReaderPDFCommand?

    func makeCoordinator() -> Coordinator {
        Coordinator(selectionBinding: $selectionState)
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = .windowBackgroundColor
        context.coordinator.configure(pdfView: view)
        context.coordinator.loadDocumentIfNeeded(from: url, into: view)
        context.coordinator.reconcileAnnotations(annotations, in: view)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        context.coordinator.selectionBinding = $selectionState
        context.coordinator.loadDocumentIfNeeded(from: url, into: nsView)
        context.coordinator.reconcileAnnotations(annotations, in: nsView)
        context.coordinator.apply(command: command, annotations: annotations, in: nsView)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selectionBinding: Binding<ReaderPDFSelectionState>
        private weak var observedPDFView: PDFView?
        private var loadedURL: URL?
        private var handledCommandID: UUID?

        init(selectionBinding: Binding<ReaderPDFSelectionState>) {
            self.selectionBinding = selectionBinding
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func configure(pdfView: PDFView) {
            guard observedPDFView !== pdfView else { return }
            NotificationCenter.default.removeObserver(self)
            observedPDFView = pdfView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleSelectionChanged(_:)),
                name: Notification.Name.PDFViewSelectionChanged,
                object: pdfView
            )
        }

        func loadDocumentIfNeeded(from url: URL, into pdfView: PDFView) {
            guard loadedURL != url else { return }
            pdfView.document = PDFDocument(url: url)
            loadedURL = url
            handledCommandID = nil
            selectionBinding.wrappedValue = .none
        }

        func reconcileAnnotations(_ annotations: [PaperAnnotation], in pdfView: PDFView) {
            guard let document = pdfView.document else { return }

            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                for annotation in page.annotations where annotation.userName?.hasPrefix("henrypaper:") == true {
                    page.removeAnnotation(annotation)
                }
            }

            for annotation in annotations {
                guard let page = document.page(at: annotation.pageIndex) else { continue }
                for (rectIndex, rect) in annotation.rects.enumerated() {
                    let overlay = PDFAnnotation(bounds: rect.cgRect, forType: .highlight, withProperties: nil)
                    overlay.color = annotation.color.pdfColor
                    overlay.userName = "henrypaper:\(annotation.id.uuidString):\(rectIndex)"
                    page.addAnnotation(overlay)
                }
            }
        }

        func apply(command: ReaderPDFCommand?, annotations: [PaperAnnotation], in pdfView: PDFView) {
            guard let command, handledCommandID != command.id else { return }
            handledCommandID = command.id

            switch command.kind {
            case .clearSelection:
                pdfView.clearSelection()
                selectionBinding.wrappedValue = .none
            case let .jumpToAnnotation(annotationID):
                jump(to: annotationID, annotations: annotations, in: pdfView)
            }
        }

        private func jump(to annotationID: UUID, annotations: [PaperAnnotation], in pdfView: PDFView) {
            guard let annotation = annotations.first(where: { $0.id == annotationID }),
                  let page = pdfView.document?.page(at: annotation.pageIndex) else {
                return
            }

            let focusPoint = annotation.rects.first.map {
                CGPoint(x: $0.x, y: $0.y + $0.height)
            } ?? CGPoint.zero
            let destination = PDFDestination(page: page, at: focusPoint)
            pdfView.go(to: destination)
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
                return
            }

            selectionBinding.wrappedValue = selectionState(for: pdfView)
        }
    }
}
