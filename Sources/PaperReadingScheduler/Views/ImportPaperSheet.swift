import SwiftUI

struct ImportPaperSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router

    let settings: UserSettings
    let currentPapers: [Paper]

    @State private var sourceText = ""
    @State private var manualTitle = ""
    @State private var manualAuthors = ""
    @State private var manualAbstract = ""
    @State private var importBehavior: ImportBehavior
    @State private var isImporting = false

    init(settings: UserSettings, currentPapers: [Paper]) {
        self.settings = settings
        self.currentPapers = currentPapers
        _importBehavior = State(initialValue: settings.defaultImportBehavior)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    TextField("arXiv URL or direct PDF URL", text: $sourceText)
                        .textFieldStyle(.roundedBorder)
                    Text("Paste an arXiv abstract URL, an arXiv PDF URL, or a direct PDF link.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Manual Metadata") {
                    TextField("Title", text: $manualTitle)
                    TextField("Authors (comma separated)", text: $manualAuthors)
                    TextField("Abstract", text: $manualAbstract, axis: .vertical)
                        .lineLimit(4...8)
                    Text(tagHelperText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Import Behavior") {
                    Picker("When imported", selection: $importBehavior) {
                        ForEach(ImportBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Paper")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isImporting ? "Importing..." : "Import") {
                        Task {
                            isImporting = true
                            let request = PaperCaptureRequest(
                                sourceText: sourceText,
                                manualTitle: manualTitle,
                                manualAuthors: manualAuthors,
                                manualAbstract: manualAbstract,
                                preferredBehavior: importBehavior
                            )

                            if let paper = await services.importPaper(
                                request: request,
                                settings: settings,
                                currentPapers: currentPapers,
                                in: modelContext
                            ) {
                                router.selectedScreen = paper.status == .inbox ? .inbox : .queue
                                router.selectedPaperID = paper.id
                                dismiss()
                            }
                            isImporting = false
                        }
                    }
                    .disabled(isImporting)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    private var tagHelperText: String {
        settings.aiTaggingEnabled
            ? "Tags will be generated automatically from the paper title and abstract when AI auto-tagging is ready."
            : "Configure AI auto-tagging in Settings to generate tags automatically during import."
    }
}
