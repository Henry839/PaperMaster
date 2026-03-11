import Foundation
import SwiftData

enum FeedbackValidationError: LocalizedError, Equatable {
    case emptyIntendedAction
    case emptyFeedbackText

    var errorDescription: String? {
        switch self {
        case .emptyIntendedAction:
            return "Add what you intended to do before submitting feedback."
        case .emptyFeedbackText:
            return "Add your feedback before submitting."
        }
    }
}

struct FeedbackSubmission {
    let intendedAction: String
    let feedbackText: String

    init(intendedAction: String, feedbackText: String) throws {
        let trimmedIntendedAction = intendedAction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedIntendedAction.isEmpty == false else {
            throw FeedbackValidationError.emptyIntendedAction
        }

        let trimmedFeedbackText = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedFeedbackText.isEmpty == false else {
            throw FeedbackValidationError.emptyFeedbackText
        }

        self.intendedAction = trimmedIntendedAction
        self.feedbackText = trimmedFeedbackText
    }
}

struct FeedbackSnapshot {
    let screenRawValue: String
    let screenTitle: String
    let selectedPaperID: UUID?
    let selectedPaperTitle: String?
    let selectedPaperStatusRawValue: String?

    init(screen: AppScreen, selectedPaper: Paper?) {
        self.screenRawValue = screen.rawValue
        self.screenTitle = screen.title
        self.selectedPaperID = selectedPaper?.id
        self.selectedPaperTitle = selectedPaper?.title
        self.selectedPaperStatusRawValue = selectedPaper?.status.rawValue
    }

    var selectedPaperStatusTitle: String? {
        guard let selectedPaperStatusRawValue else { return nil }
        return PaperStatus(rawValue: selectedPaperStatusRawValue)?.title
    }

    var paperContextSummary: String? {
        guard let selectedPaperTitle else { return nil }
        guard let selectedPaperStatusTitle else { return selectedPaperTitle }
        return "\(selectedPaperTitle) (\(selectedPaperStatusTitle))"
    }
}

@Model
final class FeedbackEntry {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var screenRawValue: String
    var screenTitle: String
    var selectedPaperID: UUID?
    var selectedPaperTitle: String?
    var selectedPaperStatusRawValue: String?
    var intendedAction: String
    var feedbackText: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        screenRawValue: String,
        screenTitle: String,
        selectedPaperID: UUID? = nil,
        selectedPaperTitle: String? = nil,
        selectedPaperStatusRawValue: String? = nil,
        intendedAction: String,
        feedbackText: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.screenRawValue = screenRawValue
        self.screenTitle = screenTitle
        self.selectedPaperID = selectedPaperID
        self.selectedPaperTitle = selectedPaperTitle
        self.selectedPaperStatusRawValue = selectedPaperStatusRawValue
        self.intendedAction = intendedAction
        self.feedbackText = feedbackText
    }

    var selectedPaperStatusTitle: String? {
        guard let selectedPaperStatusRawValue else { return nil }
        return PaperStatus(rawValue: selectedPaperStatusRawValue)?.title
    }

    var paperContextSummary: String? {
        guard let selectedPaperTitle else { return nil }
        guard let selectedPaperStatusTitle else { return selectedPaperTitle }
        return "\(selectedPaperTitle) (\(selectedPaperStatusTitle))"
    }

    var exportText: String {
        var lines = [
            "Timestamp: \(createdAt.ISO8601Format())",
            "Screen: \(screenTitle)"
        ]

        if let paperContextSummary {
            lines.append("Paper: \(paperContextSummary)")
        }

        lines.append("Intended Action: \(intendedAction)")
        lines.append("Feedback:")
        lines.append(feedbackText)
        return lines.joined(separator: "\n")
    }

    static func combinedExportText(for entries: [FeedbackEntry]) -> String {
        entries
            .map(\.exportText)
            .joined(separator: "\n\n---\n\n")
    }

    static func make(
        snapshot: FeedbackSnapshot,
        submission: FeedbackSubmission,
        createdAt: Date = .now
    ) -> FeedbackEntry {
        FeedbackEntry(
            createdAt: createdAt,
            screenRawValue: snapshot.screenRawValue,
            screenTitle: snapshot.screenTitle,
            selectedPaperID: snapshot.selectedPaperID,
            selectedPaperTitle: snapshot.selectedPaperTitle,
            selectedPaperStatusRawValue: snapshot.selectedPaperStatusRawValue,
            intendedAction: submission.intendedAction,
            feedbackText: submission.feedbackText
        )
    }
}
