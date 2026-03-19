import SwiftUI

struct PaperDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router

    @Bindable var paper: Paper
    let settings: UserSettings
    let allPapers: [Paper]

    @State private var tagEditorText = ""
    @State private var showDeleteConfirmation = false
    @State private var isOpeningReader = false
    @State private var isGeneratingPaperCard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                quickActionsSection
                metadataSection
                storageSection
                bibtexSection
                tagsSection
                abstractSection
                paperCardSection
                notesSection
            }
            .padding(24)
        }
        .textSelection(.enabled)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.08), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .navigationTitle(paper.title)
        .onAppear {
            tagEditorText = paper.tagNames.joined(separator: ", ")
        }
        .onChange(of: paper.id) { _, _ in
            tagEditorText = paper.tagNames.joined(separator: ", ")
        }
        .onChange(of: paper.notes) { _, _ in
            services.persistNotes(context: modelContext)
        }
        .confirmationDialog(
            "Delete this paper?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await services.delete(
                        paper: paper,
                        allPapers: allPapers,
                        settings: settings,
                        context: modelContext
                    )
                    router.selectedPaperID = nil
                }
            }
        } message: {
            Text("The managed PDF copy, temporary reader cache, and scheduled reminders for this paper will be removed when possible.")
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(paper.title)
                .font(.system(size: 28, weight: .bold, design: .serif))
            Text(paper.authorsDisplayText)
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(paper.status.title)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())

                if let dueDate = paper.dueDate, paper.status.isActiveQueue {
                    Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if paper.managedPDFLocalURL != nil {
                    Label("Stored Locally", systemImage: "externaldrive.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else if paper.managedPDFRemoteURL != nil {
                    Label("Stored Remotely", systemImage: "externaldrive.badge.icloud")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }

                if paper.cachedPDFURL != nil {
                    Label("Reader Cache", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("Status", selection: Binding(
                    get: { paper.status },
                    set: { newStatus in
                        services.updatePaperStatus(
                            paper,
                            status: newStatus,
                            allPapers: allPapers,
                            settings: settings,
                            context: modelContext
                        )
                    }
                )) {
                    ForEach(PaperStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
            }

            HStack(spacing: 12) {
                Button(isOpeningReader ? "Opening..." : "Read In App") {
                    Task {
                        isOpeningReader = true
                        if let presentation = await services.prepareReader(
                            for: paper,
                            currentPapers: allPapers,
                            settings: settings,
                            context: modelContext
                        ) {
                            router.readerPresentation = presentation
                        }
                        isOpeningReader = false
                    }
                }
                .disabled(isOpeningReader || hasReadablePDF == false)

                Button("Open Source") {
                    services.openSource(for: paper)
                }
                .disabled(paper.sourceURL == nil)

                Button("Snooze 1 Day") {
                    services.snooze(
                        paper: paper,
                        byDays: 1,
                        allPapers: allPapers,
                        settings: settings,
                        context: modelContext
                    )
                }
                .disabled(paper.status.isActiveQueue == false)

                Button(isGeneratingPaperCard ? "Generating Card..." : (paper.paperCard == nil ? "Create Paper Card" : "Regenerate Paper Card")) {
                    Task {
                        isGeneratingPaperCard = true
                        await services.generatePaperCard(
                            for: paper,
                            settings: settings,
                            allPapers: allPapers,
                            context: modelContext
                        )
                        isGeneratingPaperCard = false
                    }
                }
                .disabled(isGeneratingPaperCard)
            }

            HStack(spacing: 12) {
                Button("Move Up") {
                    services.move(
                        paper: paper,
                        toQueueIndex: paper.queuePosition - 1,
                        allPapers: allPapers,
                        settings: settings,
                        context: modelContext
                    )
                }
                .disabled(paper.status.isActiveQueue == false || paper.queuePosition == 0)

                Button("Move Down") {
                    services.move(
                        paper: paper,
                        toQueueIndex: paper.queuePosition + 1,
                        allPapers: allPapers,
                        settings: settings,
                        context: modelContext
                    )
                }
                .disabled(paper.status.isActiveQueue == false)

                Button("Archive") {
                    services.updatePaperStatus(
                        paper,
                        status: .archived,
                        allPapers: allPapers,
                        settings: settings,
                        context: modelContext
                    )
                }

                Spacer()

                Button("Delete", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
        }
        .padding(18)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metadata")
                .font(.title3.weight(.semibold))

            if let sourceURL = paper.sourceURL {
                LabeledContent("Source") {
                    Text(sourceURL.absoluteString)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let pdfURL = paper.pdfURL {
                LabeledContent("PDF") {
                    Text(pdfURL.absoluteString)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let venueDisplayText {
                LabeledContent("Venue") {
                    Text(venueDisplayText)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let doi = paper.doi, doi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                LabeledContent("DOI") {
                    Text(doi)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            LabeledContent("Added") {
                Text(paper.dateAdded.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Storage")
                .font(.title3.weight(.semibold))

            if let managedPDFLocalURL = paper.managedPDFLocalURL {
                LabeledContent("Managed PDF") {
                    Text(managedPDFLocalURL.path)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else if let managedPDFRemoteURL = paper.managedPDFRemoteURL {
                LabeledContent("Managed PDF") {
                    Text(managedPDFRemoteURL.absoluteString)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else {
                Text("No managed PDF copy has been saved for this paper yet.")
                    .foregroundStyle(.secondary)
            }

            if let cachedPDFURL = paper.cachedPDFURL {
                LabeledContent("Reader cache") {
                    Text(cachedPDFURL.path)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else {
                Text("The reader cache is created on demand when the paper is opened in-app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var bibtexSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BibTeX")
                        .font(.title3.weight(.semibold))
                    Text("Copy the saved citation directly into your writing workflow.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Copy BibTeX", systemImage: "doc.on.doc") {
                    services.copyText(bibtexText, notice: "Copied BibTeX.")
                }
                .disabled(bibtexText.isEmpty)
            }

            if bibtexText.isEmpty {
                Text("No BibTeX saved for this paper yet.")
                    .foregroundStyle(.secondary)
            } else {
                Text(bibtexText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags")
                .font(.title3.weight(.semibold))
            if paper.tagNames.isEmpty {
                Text("No tags yet. New imports can generate them automatically when AI auto-tagging is configured.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110), spacing: 8, alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(paper.tagNames, id: \.self) { tag in
                        TagChip(name: tag)
                    }
                }
            }

            if let autoTaggingStatusMessage = paper.autoTaggingStatusMessage,
               autoTaggingStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Last auto-tagging result", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(autoTaggingStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text("AI generates tags on import. Edit them here if you want to override the saved tags.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("agents, llms, optimization", text: $tagEditorText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save Tags") {
                    services.updateTags(
                        for: paper,
                        tagString: tagEditorText,
                        allPapers: allPapers,
                        settings: settings,
                        context: modelContext
                    )
                }
                Spacer()
            }
        }
    }

    private var abstractSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Abstract")
                .font(.title3.weight(.semibold))
            if paper.abstractText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No abstract saved yet.")
                    .foregroundStyle(.secondary)
            } else {
                Text(paper.abstractText)
                    .textSelection(.enabled)
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(.title3.weight(.semibold))
            TextEditor(text: $paper.notes)
                .font(.body)
                .frame(minHeight: 220)
                .padding(8)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
    }

    private var paperCardSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paper Card")
                        .font(.title3.weight(.semibold))
                    Text("Saved locally as structured content and HTML so it can be copied, reopened, and migrated with the library.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let card = paper.paperCard {
                    HStack(spacing: 10) {
                        Button("Copy Text") {
                            services.copyPaperCardText(card)
                        }

                        Button("Copy HTML") {
                            services.copyPaperCardHTML(card)
                        }

                        Button("Open HTML") {
                            services.openPaperCardHTML(card, paper: paper)
                        }
                    }
                }
            }

            if let card = paper.paperCard {
                VStack(alignment: .leading, spacing: 14) {
                    if card.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        Text(card.headline)
                            .font(.headline)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if card.keywords.isEmpty == false {
                        FlowLayout(card.keywords) { keyword in
                            Text(keyword)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.purple.opacity(0.10))
                                .foregroundStyle(Color.purple)
                                .clipShape(Capsule())
                        }
                    }

                    ForEach(card.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(section.emoji) \(section.title)")
                                .font(.headline)
                            Text(section.body)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Paper Card Yet",
                    systemImage: "rectangle.text.magnifyingglass",
                    description: Text("Generate a Paper Card to save a reusable structured summary and an HTML version for browser viewing.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        }
    }

    private var venueDisplayText: String? {
        let trimmedVenueName = paper.venueName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVenueKey = paper.venueKey?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (trimmedVenueName, trimmedVenueKey) {
        case let (.some(name), .some(key)) where name.isEmpty == false && key.isEmpty == false:
            return "\(name) [\(key)]"
        case let (.some(name), _) where name.isEmpty == false:
            return name
        case let (_, .some(key)) where key.isEmpty == false:
            return key
        default:
            return nil
        }
    }

    private var bibtexText: String {
        paper.bibtex?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var hasReadablePDF: Bool {
        if let managedPDFLocalURL = paper.managedPDFLocalURL,
           FileManager.default.fileExists(atPath: managedPDFLocalURL.path) {
            return true
        }

        return paper.managedPDFRemoteURL != nil || paper.pdfURL != nil || paper.cachedPDFURL != nil
    }
}

private struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let content: (Data.Element) -> Content

    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let rows = makeRows(from: Array(data))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        content(item)
                    }
                }
            }
        }
    }

    private func makeRows(from items: [Data.Element]) -> [[Data.Element]] {
        var rows: [[Data.Element]] = [[]]
        for item in items {
            if rows[rows.count - 1].count >= 4 {
                rows.append([item])
            } else {
                rows[rows.count - 1].append(item)
            }
        }
        return rows.filter { $0.isEmpty == false }
    }
}
