import AppKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @Bindable var settings: UserSettings
    let allPapers: [Paper]

    @Query(sort: \FeedbackEntry.createdAt, order: .reverse) private var feedbackEntries: [FeedbackEntry]
    @State private var taggingAPIKey = ""
    @State private var didLoadTaggingAPIKey = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.system(size: 30, weight: .bold, design: .serif))

                readingDefaultsSection
                aiTaggingSection

                Text("Core reading data stays local. Scheduling is based on queue order and your papers-per-day target.")
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
            didLoadTaggingAPIKey = true
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

            Toggle("Auto-cache PDFs after import", isOn: $settings.autoCachePDFs)
                .onChange(of: settings.autoCachePDFs) { _, _ in
                    services.persistNotes(context: modelContext)
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

    private var aiTaggingSection: some View {
        let readiness = settings.aiTaggingReadiness(apiKey: taggingAPIKey)

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Tagging")
                    .font(.title3.weight(.semibold))
                Text("Generate tags automatically during import using an OpenAI-compatible provider.")
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

            Label(readiness.settingsMessage, systemImage: readinessSymbol(for: readiness))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(readinessColor(for: readiness))

            Text("Only new imports are auto-tagged. Existing papers keep their tags unless you edit them manually.")
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
                    copyText(
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
                            copyText(entry.exportText, notice: "Copied feedback.")
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

    private func copyText(_ text: String, notice: String) {
        guard text.isEmpty == false else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        services.showNotice(notice)
    }

    private func readinessSymbol(for readiness: AITaggingReadiness) -> String {
        switch readiness {
        case .disabled:
            "bolt.slash"
        case .ready:
            "checkmark.circle.fill"
        case .missingBaseURL, .invalidBaseURL, .missingModel, .missingAPIKey:
            "exclamationmark.triangle.fill"
        }
    }

    private func readinessColor(for readiness: AITaggingReadiness) -> Color {
        switch readiness {
        case .disabled:
            .secondary
        case .ready:
            .green
        case .missingBaseURL, .invalidBaseURL, .missingModel, .missingAPIKey:
            .orange
        }
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
