import SwiftData
import SwiftUI

struct FeedbackCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    let snapshot: FeedbackSnapshot

    @State private var intendedAction = ""
    @State private var feedbackText = ""
    @State private var validationMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case intendedAction
        case feedback
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Share Feedback")
                .font(.system(size: 24, weight: .bold, design: .serif))

            Text("Capture what you were trying to do and what happened so you can review it later.")
                .foregroundStyle(.secondary)

            GroupBox("Current Context") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Screen") {
                        Text(snapshot.screenTitle)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Paper") {
                        Text(snapshot.paperContextSummary ?? "No paper selected")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Intended Action")
                    .font(.headline)
                TextField("What were you trying to do?", text: $intendedAction)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .intendedAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Feedback")
                    .font(.headline)
                TextEditor(text: $feedbackText)
                    .font(.body)
                    .frame(minHeight: 190)
                    .padding(8)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .focused($focusedField, equals: .feedback)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }

                Button("Submit") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.08), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            focusedField = .intendedAction
        }
    }

    private func submit() {
        do {
            let submission = try FeedbackSubmission(
                intendedAction: intendedAction,
                feedbackText: feedbackText
            )
            try services.saveFeedback(
                snapshot: snapshot,
                submission: submission,
                context: modelContext
            )
            intendedAction = ""
            feedbackText = ""
            validationMessage = nil
            dismiss()
        } catch let error as FeedbackValidationError {
            validationMessage = error.errorDescription
            focusedField = error == .emptyIntendedAction ? .intendedAction : .feedback
        } catch {
            validationMessage = nil
        }
    }
}
