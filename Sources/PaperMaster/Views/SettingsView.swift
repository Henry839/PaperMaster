import SwiftData
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @Bindable var settings: UserSettings
    let allPapers: [Paper]

    @Query(sort: \FeedbackEntry.createdAt, order: .reverse) private var feedbackEntries: [FeedbackEntry]
    @State private var taggingAPIKey = ""
    @State private var didLoadTaggingAPIKey = false
    @State private var paperStoragePassword = ""
    @State private var hasSavedPaperStoragePassword = false
    @State private var isPaperStorageFolderImporterPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.system(size: 30, weight: .bold, design: .serif))

                readingDefaultsSection
                paperStorageSection
                aiTaggingSection

                Text("Library metadata stays local. New imports use the selected paper storage target, and scheduling still follows queue order and your papers-per-day target.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                feedbackLogSection
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
        .task {
            guard didLoadTaggingAPIKey == false else { return }
            taggingAPIKey = services.loadTaggingAPIKey()
            hasSavedPaperStoragePassword = services.hasSavedPaperStoragePassword(for: settings)
            didLoadTaggingAPIKey = true
        }
        .fileImporter(
            isPresented: $isPaperStorageFolderImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result,
                  let selectedURL = urls.first else {
                return
            }
            services.setCustomPaperStorageFolder(
                selectedURL,
                for: settings,
                context: modelContext
            )
        }
    }

    private var readingDefaultsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Reading Defaults")
                .font(.title3.weight(.semibold))

            Stepper(value: $settings.papersPerDay, in: 1...10) {
                Text("Papers per day: \(settings.papersPerDay)")
            }
            .onChange(of: settings.papersPerDay) { _, _ in
                services.refreshScheduleAndNotifications(
                    papers: allPapers,
                    settings: settings,
                    context: modelContext
                )
            }

            DatePicker(
                "Daily reminder time",
                selection: $settings.dailyReminderTime,
                displayedComponents: .hourAndMinute
            )
            .onChange(of: settings.dailyReminderTime) { _, _ in
                services.refreshScheduleAndNotifications(
                    papers: allPapers,
                    settings: settings,
                    context: modelContext
                )
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Default import behavior")
                Spacer()
                Picker(
                    "Default import behavior",
                    selection: Binding(
                        get: { settings.defaultImportBehavior },
                        set: { newValue in
                            settings.defaultImportBehavior = newValue
                            services.persistNotes(context: modelContext)
                        }
                    )
                ) {
                    ForEach(ImportBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var paperStorageSection: some View {
        let readiness = settings.paperStorageReadiness(
            defaultDirectoryURL: services.defaultPaperStorageDirectoryURL,
            hasRemotePassword: hasSavedPaperStoragePassword || typedPaperStoragePasswordIsPresent,
            capabilities: services.platformCapabilities
        )
        let availableStorageModes = PaperStorageMode.supportedCases(capabilities: services.platformCapabilities)

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Paper Storage")
                    .font(.title3.weight(.semibold))
                Text("Managed PDF copies are stored during import. Existing stored PDFs stay where they already are.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Storage target")
                Spacer()
                Picker(
                    "Storage target",
                    selection: Binding(
                        get: { settings.paperStorageMode },
                        set: { newValue in
                            settings.paperStorageMode = newValue
                            persistPaperStorageSettings()
                        }
                    )
                ) {
                    ForEach(availableStorageModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            switch settings.paperStorageMode {
            case .defaultLocal:
                LabeledContent("Default folder") {
                    Text(services.defaultPaperStorageDirectoryPath)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            case .customLocal:
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Local paper storage folder", text: $settings.customPaperStoragePath)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.customPaperStoragePath) { _, _ in
                            persistPaperStorageSettings()
                        }

                    HStack(spacing: 12) {
                        Button("Choose Folder") {
                            choosePaperStorageFolder()
                        }

                        if settings.customPaperStoragePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                            Text(settings.customPaperStorageFolderDisplayName.isEmpty ? settings.customPaperStoragePath : settings.customPaperStorageFolderDisplayName)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            case .remoteSSH:
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Host", text: $settings.remotePaperStorageHost)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.remotePaperStorageHost) { _, _ in
                            refreshRemotePaperStorageIdentity()
                        }

                    TextField("Port", value: $settings.remotePaperStoragePort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.remotePaperStoragePort) { _, _ in
                            refreshRemotePaperStorageIdentity()
                        }

                    TextField("Username", text: $settings.remotePaperStorageUsername)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.remotePaperStorageUsername) { _, _ in
                            refreshRemotePaperStorageIdentity()
                        }

                    TextField("Remote directory", text: $settings.remotePaperStorageDirectory)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.remotePaperStorageDirectory) { _, _ in
                            persistPaperStorageSettings()
                        }

                    HStack(alignment: .center, spacing: 12) {
                        SecureField("SSH password", text: $paperStoragePassword)
                            .textFieldStyle(.roundedBorder)

                        Button("Save Password") {
                            services.savePaperStoragePassword(paperStoragePassword, for: settings)
                            paperStoragePassword = ""
                            hasSavedPaperStoragePassword = services.hasSavedPaperStoragePassword(for: settings)
                        }
                        .disabled(typedPaperStoragePasswordIsPresent == false)

                        Button("Clear") {
                            paperStoragePassword = ""
                            services.clearPaperStoragePassword(for: settings)
                            hasSavedPaperStoragePassword = false
                        }
                        .disabled(hasSavedPaperStoragePassword == false && typedPaperStoragePasswordIsPresent == false)
                    }

                    Text(hasSavedPaperStoragePassword ? "A password is saved in Keychain for this SSH target." : "No SSH password is saved for this SSH target yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Label(readiness.settingsMessage, systemImage: paperStorageReadinessSymbol(for: readiness))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(paperStorageReadinessColor(for: readiness))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var aiTaggingSection: some View {
        let providerReadiness = settings.aiProviderReadiness(apiKey: taggingAPIKey)

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Provider")
                    .font(.title3.weight(.semibold))
                Text("Reader Ask AI, Paper Fusion Reactor, and optional import auto-tagging all use this OpenAI-compatible provider.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Toggle("Automatically generate tags on import", isOn: $settings.aiTaggingEnabled)
                .onChange(of: settings.aiTaggingEnabled) { _, _ in
                    services.persistNotes(context: modelContext)
                }

            TextField("Base URL", text: $settings.aiTaggingBaseURLString)
                .textFieldStyle(.roundedBorder)
                .onChange(of: settings.aiTaggingBaseURLString) { _, _ in
                    services.persistNotes(context: modelContext)
                }

            TextField("Model", text: $settings.aiTaggingModel)
                .textFieldStyle(.roundedBorder)
                .onChange(of: settings.aiTaggingModel) { _, _ in
                    services.persistNotes(context: modelContext)
                }

            HStack(alignment: .center, spacing: 12) {
                SecureField("API key", text: $taggingAPIKey)
                    .textFieldStyle(.roundedBorder)

                Button("Save Key") {
                    services.saveTaggingAPIKey(taggingAPIKey)
                    taggingAPIKey = services.loadTaggingAPIKey()
                }

                Button("Clear") {
                    taggingAPIKey = ""
                    services.saveTaggingAPIKey("")
                }
                .disabled(taggingAPIKey.isEmpty)
            }

            Label(providerReadiness.settingsMessage, systemImage: readinessSymbol(for: providerReadiness))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(readinessColor(for: providerReadiness))

            Text("Turn on the import toggle if you want new papers auto-tagged. Reader Ask AI and Fusion Reactor can still use the provider even when import auto-tagging is off.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var feedbackLogSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Feedback Log")
                        .font(.title3.weight(.semibold))
                    Text("Stored locally so you can manually collect and share it later.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Copy All Feedback", systemImage: "doc.on.doc") {
                    services.copyText(
                        FeedbackEntry.combinedExportText(for: feedbackEntries),
                        notice: "Copied all feedback."
                    )
                }
                .disabled(feedbackEntries.isEmpty)
            }

            if feedbackEntries.isEmpty {
                ContentUnavailableView(
                    "No feedback yet",
                    systemImage: "square.and.pencil",
                    description: Text("Use the Feedback button in the toolbar to save notes about what you were trying to do.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(feedbackEntries) { entry in
                        FeedbackLogRow(entry: entry) {
                            services.copyText(entry.exportText, notice: "Copied feedback.")
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func readinessSymbol(for readiness: AIProviderReadiness) -> String {
        switch readiness {
        case .ready:
            "checkmark.circle.fill"
        case .missingBaseURL, .invalidBaseURL, .missingModel, .missingAPIKey:
            "exclamationmark.triangle.fill"
        }
    }

    private func readinessColor(for readiness: AIProviderReadiness) -> Color {
        switch readiness {
        case .ready:
            .green
        case .missingBaseURL, .invalidBaseURL, .missingModel, .missingAPIKey:
            .orange
        }
    }

    private func paperStorageReadinessSymbol(for readiness: PaperStorageReadiness) -> String {
        readiness.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private func paperStorageReadinessColor(for readiness: PaperStorageReadiness) -> Color {
        readiness.isReady ? .green : .orange
    }

    private var typedPaperStoragePasswordIsPresent: Bool {
        paperStoragePassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func persistPaperStorageSettings() {
        services.persistNotes(context: modelContext)
        services.refreshStorageFolderMonitoring(context: modelContext)
    }

    private func refreshRemotePaperStorageIdentity() {
        persistPaperStorageSettings()
        hasSavedPaperStoragePassword = services.hasSavedPaperStoragePassword(for: settings)
    }

    private func choosePaperStorageFolder() {
        #if os(iOS)
        isPaperStorageFolderImporterPresented = true
        #else
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        let trimmedPath = settings.customPaperStoragePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPath.isEmpty == false {
            panel.directoryURL = URL(fileURLWithPath: trimmedPath, isDirectory: true)
        } else {
            panel.directoryURL = services.defaultPaperStorageDirectoryURL
        }

        if panel.runModal() == .OK, let selectedURL = panel.url {
            services.setCustomPaperStorageFolder(
                selectedURL,
                for: settings,
                context: modelContext
            )
        }
        #endif
    }
}

private struct FeedbackLogRow: View {
    let entry: FeedbackEntry
    let copyAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline.weight(.semibold))
                    Text(entry.screenTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if let paperContextSummary = entry.paperContextSummary {
                        Text(paperContextSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Copy", systemImage: "doc.on.doc") {
                    copyAction()
                }
                .labelStyle(.titleAndIcon)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Intended Action")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(entry.intendedAction)
                    .font(.body.weight(.medium))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Feedback")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(entry.feedbackText)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
