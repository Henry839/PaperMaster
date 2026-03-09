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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                quickActionsSection
                metadataSection
                tagsSection
                abstractSection
                notesSection
            }
            .padding(24)
        }
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
                services.delete(
                    paper: paper,
                    allPapers: allPapers,
                    settings: settings,
                    context: modelContext
                )
                router.selectedPaperID = nil
            }
        } message: {
            Text("The cached PDF and scheduled reminders for this paper will be removed.")
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

                if paper.cachedPDFURL != nil {
                    Label("Cached", systemImage: "checkmark.circle.fill")
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
                .disabled(isOpeningReader || (paper.pdfURL == nil && paper.cachedPDFURL == nil))

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
            }

            HStack(spacing: 12) {
                Button("Move Up") {
                    services.move(
                        paper: paper,
                        by: -1,
                        allPapers: allPapers,
                        settings: settings,
                        context: modelContext
                    )
                }
                .disabled(paper.status.isActiveQueue == false || paper.queuePosition == 0)

                Button("Move Down") {
                    services.move(
                        paper: paper,
                        by: 1,
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

            LabeledContent("Added") {
                Text(paper.dateAdded.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
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
}
