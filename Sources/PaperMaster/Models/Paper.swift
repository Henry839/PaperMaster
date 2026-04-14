import Foundation
#if PAPERMASTER_LEGACY_MODE
import Combine
#else
import SwiftData
#endif

#if PAPERMASTER_LEGACY_MODE
final class Paper: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    @Published var authorsText: String
    @Published var abstractText: String
    @Published var venueKey: String?
    @Published var venueName: String?
    @Published var doi: String?
    @Published var bibtex: String?
    @Published var sourceURLString: String?
    @Published var pdfURLString: String?
    @Published var cachedPDFPath: String?
    @Published var managedPDFLocalPath: String?
    @Published var managedPDFRemoteURLString: String?
    @Published var statusRawValue: String
    @Published var queuePosition: Int
    @Published var dateAdded: Date
    @Published var dueDate: Date?
    @Published var manualDueDateOverride: Date?
    @Published var startedAt: Date?
    @Published var completedAt: Date?
    @Published var notes: String
    @Published var autoTaggingStatusMessage: String?
    @Published var tags: [Tag] {
        didSet { synchronizeRelationships() }
    }
    @Published var annotations: [PaperAnnotation] {
        didSet { synchronizeRelationships() }
    }
    @Published var paperCard: PaperCard? {
        didSet { synchronizeRelationships() }
    }

    private var childCancellables: Set<AnyCancellable> = []

    init(
        id: UUID = UUID(),
        title: String,
        authors: [String] = [],
        abstractText: String = "",
        venueKey: String? = nil,
        venueName: String? = nil,
        doi: String? = nil,
        bibtex: String? = nil,
        sourceURL: URL? = nil,
        pdfURL: URL? = nil,
        cachedPDFPath: String? = nil,
        managedPDFLocalPath: String? = nil,
        managedPDFRemoteURLString: String? = nil,
        status: PaperStatus = .inbox,
        queuePosition: Int = 0,
        dateAdded: Date = .now,
        dueDate: Date? = nil,
        manualDueDateOverride: Date? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        notes: String = "",
        autoTaggingStatusMessage: String? = nil,
        tags: [Tag] = [],
        annotations: [PaperAnnotation] = [],
        paperCard: PaperCard? = nil
    ) {
        self.id = id
        self.title = title
        self.authorsText = authors.joined(separator: ", ")
        self.abstractText = abstractText
        self.venueKey = venueKey
        self.venueName = venueName
        self.doi = doi
        self.bibtex = bibtex
        self.sourceURLString = sourceURL?.absoluteString
        self.pdfURLString = pdfURL?.absoluteString
        self.cachedPDFPath = cachedPDFPath
        self.managedPDFLocalPath = managedPDFLocalPath
        self.managedPDFRemoteURLString = managedPDFRemoteURLString
        self.statusRawValue = status.rawValue
        self.queuePosition = queuePosition
        self.dateAdded = dateAdded
        self.dueDate = dueDate
        self.manualDueDateOverride = manualDueDateOverride
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.notes = notes
        self.autoTaggingStatusMessage = autoTaggingStatusMessage
        self.tags = tags
        self.annotations = annotations
        self.paperCard = paperCard
        synchronizeRelationships()
    }

    convenience init(snapshot: PaperSnapshot) {
        self.init(
            id: snapshot.id,
            title: snapshot.title,
            authors: snapshot.authors,
            abstractText: snapshot.abstractText,
            venueKey: snapshot.venueKey,
            venueName: snapshot.venueName,
            doi: snapshot.doi,
            bibtex: snapshot.bibtex,
            sourceURL: snapshot.sourceURLString.flatMap(URL.init(string:)),
            pdfURL: snapshot.pdfURLString.flatMap(URL.init(string:)),
            cachedPDFPath: snapshot.cachedPDFPath,
            managedPDFLocalPath: snapshot.managedPDFLocalPath,
            managedPDFRemoteURLString: snapshot.managedPDFRemoteURLString,
            status: PaperStatus(rawValue: snapshot.statusRawValue) ?? .inbox,
            queuePosition: snapshot.queuePosition,
            dateAdded: snapshot.dateAdded,
            dueDate: snapshot.dueDate,
            manualDueDateOverride: snapshot.manualDueDateOverride,
            startedAt: snapshot.startedAt,
            completedAt: snapshot.completedAt,
            notes: snapshot.notes,
            autoTaggingStatusMessage: snapshot.autoTaggingStatusMessage,
            tags: snapshot.tags.map(Tag.init(snapshot:)),
            annotations: snapshot.annotations.map(PaperAnnotation.init(snapshot:)),
            paperCard: snapshot.paperCard.map(PaperCard.init(snapshot:))
        )
    }

    var snapshot: PaperSnapshot {
        PaperSnapshot(
            id: id,
            title: title,
            authors: authors,
            abstractText: abstractText,
            venueKey: venueKey,
            venueName: venueName,
            doi: doi,
            bibtex: bibtex,
            sourceURLString: sourceURLString,
            pdfURLString: pdfURLString,
            cachedPDFPath: cachedPDFPath,
            managedPDFLocalPath: managedPDFLocalPath,
            managedPDFRemoteURLString: managedPDFRemoteURLString,
            statusRawValue: statusRawValue,
            queuePosition: queuePosition,
            dateAdded: dateAdded,
            dueDate: dueDate,
            manualDueDateOverride: manualDueDateOverride,
            startedAt: startedAt,
            completedAt: completedAt,
            notes: notes,
            autoTaggingStatusMessage: autoTaggingStatusMessage,
            tags: tags.map(\.snapshot),
            annotations: annotations.map(\.snapshot),
            paperCard: paperCard?.snapshot
        )
    }

    private func synchronizeRelationships() {
        childCancellables.removeAll()

        for tag in tags {
            tag.paper = self
            tag.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &childCancellables)
        }

        for annotation in annotations {
            annotation.paper = self
            annotation.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &childCancellables)
        }

        if let paperCard {
            paperCard.paper = self
            paperCard.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &childCancellables)
        }
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

    var managedPDFLocalURL: URL? {
        get {
            guard let managedPDFLocalPath else { return nil }
            return URL(fileURLWithPath: managedPDFLocalPath)
        }
        set {
            managedPDFLocalPath = newValue?.path
        }
    }

    var managedPDFRemoteURL: URL? {
        get { managedPDFRemoteURLString.flatMap(URL.init(string:)) }
        set { managedPDFRemoteURLString = newValue?.absoluteString }
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
            venueKey ?? "",
            venueName ?? "",
            doi ?? "",
            tagNames.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()

        return haystack.contains(trimmed.lowercased())
    }

    var paperIdentityKeys: Set<String> {
        var keys: Set<String> = []

        if let sourceURL {
            keys.formUnion(sourceURL.canonicalPaperIdentityKeys)
        }

        if let pdfURL {
            keys.formUnion(pdfURL.canonicalPaperIdentityKeys)
        }

        if let doi = doi?.normalizedPaperIdentityDOI, doi.isEmpty == false {
            keys.insert("doi:\(doi)")
        }

        return keys
    }
}

struct PaperSnapshot: Codable {
    let id: UUID
    let title: String
    let authors: [String]
    let abstractText: String
    let venueKey: String?
    let venueName: String?
    let doi: String?
    let bibtex: String?
    let sourceURLString: String?
    let pdfURLString: String?
    let cachedPDFPath: String?
    let managedPDFLocalPath: String?
    let managedPDFRemoteURLString: String?
    let statusRawValue: String
    let queuePosition: Int
    let dateAdded: Date
    let dueDate: Date?
    let manualDueDateOverride: Date?
    let startedAt: Date?
    let completedAt: Date?
    let notes: String
    let autoTaggingStatusMessage: String?
    let tags: [TagSnapshot]
    let annotations: [PaperAnnotationSnapshot]
    let paperCard: PaperCardSnapshot?
}
#else
@Model
final class Paper {
    @Attribute(.unique) var id: UUID
    var title: String
    var authorsText: String
    var abstractText: String
    var venueKey: String?
    var venueName: String?
    var doi: String?
    var bibtex: String?
    var sourceURLString: String?
    var pdfURLString: String?
    var cachedPDFPath: String?
    var managedPDFLocalPath: String?
    var managedPDFRemoteURLString: String?
    var statusRawValue: String
    var queuePosition: Int
    var dateAdded: Date
    var dueDate: Date?
    var manualDueDateOverride: Date?
    var startedAt: Date?
    var completedAt: Date?
    var notes: String
    var autoTaggingStatusMessage: String?
    @Relationship(deleteRule: .cascade, inverse: \Tag.paper) var tags: [Tag]
    @Relationship(deleteRule: .cascade, inverse: \PaperAnnotation.paper) var annotations: [PaperAnnotation]
    @Relationship(deleteRule: .cascade, inverse: \PaperCard.paper) var paperCard: PaperCard?

    init(
        id: UUID = UUID(),
        title: String,
        authors: [String] = [],
        abstractText: String = "",
        venueKey: String? = nil,
        venueName: String? = nil,
        doi: String? = nil,
        bibtex: String? = nil,
        sourceURL: URL? = nil,
        pdfURL: URL? = nil,
        cachedPDFPath: String? = nil,
        managedPDFLocalPath: String? = nil,
        managedPDFRemoteURLString: String? = nil,
        status: PaperStatus = .inbox,
        queuePosition: Int = 0,
        dateAdded: Date = .now,
        dueDate: Date? = nil,
        manualDueDateOverride: Date? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        notes: String = "",
        autoTaggingStatusMessage: String? = nil,
        tags: [Tag] = [],
        annotations: [PaperAnnotation] = [],
        paperCard: PaperCard? = nil
    ) {
        self.id = id
        self.title = title
        self.authorsText = authors.joined(separator: ", ")
        self.abstractText = abstractText
        self.venueKey = venueKey
        self.venueName = venueName
        self.doi = doi
        self.bibtex = bibtex
        self.sourceURLString = sourceURL?.absoluteString
        self.pdfURLString = pdfURL?.absoluteString
        self.cachedPDFPath = cachedPDFPath
        self.managedPDFLocalPath = managedPDFLocalPath
        self.managedPDFRemoteURLString = managedPDFRemoteURLString
        self.statusRawValue = status.rawValue
        self.queuePosition = queuePosition
        self.dateAdded = dateAdded
        self.dueDate = dueDate
        self.manualDueDateOverride = manualDueDateOverride
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.notes = notes
        self.autoTaggingStatusMessage = autoTaggingStatusMessage
        self.tags = tags
        self.annotations = annotations
        self.paperCard = paperCard
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

    var managedPDFLocalURL: URL? {
        get {
            guard let managedPDFLocalPath else { return nil }
            return URL(fileURLWithPath: managedPDFLocalPath)
        }
        set {
            managedPDFLocalPath = newValue?.path
        }
    }

    var managedPDFRemoteURL: URL? {
        get { managedPDFRemoteURLString.flatMap(URL.init(string:)) }
        set { managedPDFRemoteURLString = newValue?.absoluteString }
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
            venueKey ?? "",
            venueName ?? "",
            doi ?? "",
            tagNames.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()

        return haystack.contains(trimmed.lowercased())
    }

    var paperIdentityKeys: Set<String> {
        var keys: Set<String> = []

        if let sourceURL {
            keys.formUnion(sourceURL.canonicalPaperIdentityKeys)
        }

        if let pdfURL {
            keys.formUnion(pdfURL.canonicalPaperIdentityKeys)
        }

        if let doi = doi?.normalizedPaperIdentityDOI, doi.isEmpty == false {
            keys.insert("doi:\(doi)")
        }

        return keys
    }
}
#endif

private extension String {
    var normalizedPaperIdentityDOI: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "https://doi.org/", with: "")
            .replacingOccurrences(of: "http://doi.org/", with: "")
            .replacingOccurrences(of: "doi:", with: "")
    }
}
