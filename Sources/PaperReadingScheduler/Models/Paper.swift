import Foundation
import SwiftData

@Model
final class Paper {
    @Attribute(.unique) var id: UUID
    var title: String
    var authorsText: String
    var abstractText: String
    var sourceURLString: String?
    var pdfURLString: String?
    var cachedPDFPath: String?
    var statusRawValue: String
    var queuePosition: Int
    var dateAdded: Date
    var dueDate: Date?
    var manualDueDateOverride: Date?
    var startedAt: Date?
    var completedAt: Date?
    var notes: String
    var tags: [Tag]

    init(
        id: UUID = UUID(),
        title: String,
        authors: [String] = [],
        abstractText: String = "",
        sourceURL: URL? = nil,
        pdfURL: URL? = nil,
        cachedPDFPath: String? = nil,
        status: PaperStatus = .inbox,
        queuePosition: Int = 0,
        dateAdded: Date = .now,
        dueDate: Date? = nil,
        manualDueDateOverride: Date? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        notes: String = "",
        tags: [Tag] = []
    ) {
        self.id = id
        self.title = title
        self.authorsText = authors.joined(separator: ", ")
        self.abstractText = abstractText
        self.sourceURLString = sourceURL?.absoluteString
        self.pdfURLString = pdfURL?.absoluteString
        self.cachedPDFPath = cachedPDFPath
        self.statusRawValue = status.rawValue
        self.queuePosition = queuePosition
        self.dateAdded = dateAdded
        self.dueDate = dueDate
        self.manualDueDateOverride = manualDueDateOverride
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.notes = notes
        self.tags = tags
    }

    var status: PaperStatus {
        get { PaperStatus(rawValue: statusRawValue) ?? .inbox }
        set { statusRawValue = newValue.rawValue }
    }

    var authors: [String] {
        get {
            authorsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            authorsText = newValue.joined(separator: ", ")
        }
    }

    var sourceURL: URL? {
        get { sourceURLString.flatMap(URL.init(string:)) }
        set { sourceURLString = newValue?.absoluteString }
    }

    var pdfURL: URL? {
        get { pdfURLString.flatMap(URL.init(string:)) }
        set { pdfURLString = newValue?.absoluteString }
    }

    var cachedPDFURL: URL? {
        get {
            guard let cachedPDFPath else { return nil }
            return URL(fileURLWithPath: cachedPDFPath)
        }
        set {
            cachedPDFPath = newValue?.path
        }
    }

    var tagNames: [String] {
        tags.map(\.name).sorted()
    }

    var authorsDisplayText: String {
        let authorList = authors
        return authorList.isEmpty ? "Unknown authors" : authorList.joined(separator: ", ")
    }

    func isDueTodayOrOverdue(calendar: Calendar = .current, referenceDate: Date = .now) -> Bool {
        guard let dueDate else { return false }
        let dueDay = calendar.startOfDay(for: dueDate)
        let today = calendar.startOfDay(for: referenceDate)
        return dueDay <= today && status.isActiveQueue
    }

    func matchesSearch(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let haystack = [
            title,
            authorsText,
            abstractText,
            tagNames.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()

        return haystack.contains(trimmed.lowercased())
    }
}
