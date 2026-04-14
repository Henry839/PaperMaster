#if PAPERMASTER_LEGACY_MODE
import Combine
import Foundation
import SwiftUI

struct FetchDescriptor<Model> {
    init() {}
}

final class ModelContainer {
    let store: LegacyLibraryStore
    let mainContext: ModelContext

    init(store: LegacyLibraryStore) {
        self.store = store
        self.mainContext = ModelContext(store: store)
    }
}

final class ModelContext {
    let store: LegacyLibraryStore

    init(store: LegacyLibraryStore) {
        self.store = store
    }

    func insert<Model>(_ model: Model) {
        switch model {
        case let paper as Paper:
            store.insert(paper)
        case let settings as UserSettings:
            store.insert(settings)
        case let entry as FeedbackEntry:
            store.insert(entry)
        case let annotation as PaperAnnotation:
            guard let paper = annotation.paper else { return }
            if paper.annotations.contains(where: { $0.id == annotation.id }) == false {
                paper.annotations.append(annotation)
            }
        case let card as PaperCard:
            guard let paper = card.paper else { return }
            if paper.paperCard?.id != card.id {
                paper.paperCard = card
            }
        case let tag as Tag:
            guard let paper = tag.paper else { return }
            if paper.tags.contains(where: { $0 === tag }) == false {
                paper.tags.append(tag)
            }
        default:
            break
        }
    }

    func delete<Model>(_ model: Model) {
        switch model {
        case let paper as Paper:
            store.delete(paper)
        case let settings as UserSettings:
            store.delete(settings)
        case let entry as FeedbackEntry:
            store.delete(entry)
        case let annotation as PaperAnnotation:
            if let paper = annotation.paper {
                paper.annotations.removeAll { $0.id == annotation.id }
            } else {
                for paper in store.papers {
                    paper.annotations.removeAll { $0.id == annotation.id }
                }
            }
        case let card as PaperCard:
            if let paper = card.paper, paper.paperCard?.id == card.id {
                paper.paperCard = nil
            } else {
                for paper in store.papers where paper.paperCard?.id == card.id {
                    paper.paperCard = nil
                }
            }
        case let tag as Tag:
            if let paper = tag.paper {
                paper.tags.removeAll { $0 === tag }
            } else {
                for paper in store.papers {
                    paper.tags.removeAll { $0 === tag }
                }
            }
        default:
            break
        }
    }

    func fetch<Model>(_ descriptor: FetchDescriptor<Model>) throws -> [Model] {
        _ = descriptor

        switch Model.self {
        case is Paper.Type:
            return store.papers as? [Model] ?? []
        case is UserSettings.Type:
            return store.settingsList as? [Model] ?? []
        case is FeedbackEntry.Type:
            return store.feedbackEntries as? [Model] ?? []
        case is Tag.Type:
            return store.papers.flatMap(\.tags) as? [Model] ?? []
        default:
            return []
        }
    }

    func save() throws {
        try store.save()
    }
}

private struct LegacyModelContextKey: EnvironmentKey {
    static let defaultValue = ModelContainer(store: .inMemory()).mainContext
}

extension EnvironmentValues {
    var modelContext: ModelContext {
        get { self[LegacyModelContextKey.self] }
        set { self[LegacyModelContextKey.self] = newValue }
    }
}

extension View {
    func modelContainer(_ container: ModelContainer) -> some View {
        environment(\.modelContext, container.mainContext)
            .environmentObject(container.store)
    }
}

extension Scene {
    func modelContainer(_ container: ModelContainer) -> some Scene {
        environment(\.modelContext, container.mainContext)
    }
}

final class LegacyLibraryStore: ObservableObject {
    @Published private(set) var papers: [Paper]
    @Published private(set) var settingsList: [UserSettings]
    @Published private(set) var feedbackEntries: [FeedbackEntry]

    let fileURL: URL?

    private let fileManager: FileManager
    private var childCancellables: Set<AnyCancellable> = []

    init(
        fileURL: URL?,
        fileManager: FileManager = .default,
        papers: [Paper] = [],
        settingsList: [UserSettings] = [],
        feedbackEntries: [FeedbackEntry] = []
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.papers = papers
        self.settingsList = settingsList
        self.feedbackEntries = feedbackEntries
        wireChildObservers()
    }

    static func inMemory() -> LegacyLibraryStore {
        LegacyLibraryStore(fileURL: nil)
    }

    static func load(from fileURL: URL, fileManager: FileManager = .default) throws -> LegacyLibraryStore {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return LegacyLibraryStore(fileURL: fileURL, fileManager: fileManager)
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LegacyLibrarySnapshot.self, from: data)

        return LegacyLibraryStore(
            fileURL: fileURL,
            fileManager: fileManager,
            papers: snapshot.papers.map(Paper.init(snapshot:)),
            settingsList: snapshot.settingsList.map(UserSettings.init(snapshot:)),
            feedbackEntries: snapshot.feedbackEntries.map(FeedbackEntry.init(snapshot:))
        )
    }

    func insert(_ paper: Paper) {
        upsert(&papers, element: paper, matches: { $0.id == paper.id })
        wireChildObservers()
    }

    func insert(_ settings: UserSettings) {
        upsert(&settingsList, element: settings, matches: { $0.id == settings.id })
        wireChildObservers()
    }

    func insert(_ entry: FeedbackEntry) {
        upsert(&feedbackEntries, element: entry, matches: { $0.id == entry.id })
    }

    func delete(_ paper: Paper) {
        papers.removeAll { $0.id == paper.id }
        wireChildObservers()
    }

    func delete(_ settings: UserSettings) {
        settingsList.removeAll { $0.id == settings.id }
        wireChildObservers()
    }

    func delete(_ entry: FeedbackEntry) {
        feedbackEntries.removeAll { $0.id == entry.id }
    }

    func save() throws {
        guard let fileURL else { return }

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let snapshot = LegacyLibrarySnapshot(
            papers: papers.map(\.snapshot),
            settingsList: settingsList.map(\.snapshot),
            feedbackEntries: feedbackEntries.map(\.snapshot)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    private func wireChildObservers() {
        childCancellables.removeAll()

        for paper in papers {
            paper.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &childCancellables)
        }

        for settings in settingsList {
            settings.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &childCancellables)
        }
    }

    private func upsert<Element>(
        _ elements: inout [Element],
        element: Element,
        matches: (Element) -> Bool
    ) {
        if let index = elements.firstIndex(where: matches) {
            elements[index] = element
        } else {
            elements.append(element)
        }
    }
}

private struct LegacyLibrarySnapshot: Codable {
    let papers: [PaperSnapshot]
    let settingsList: [UserSettingsSnapshot]
    let feedbackEntries: [FeedbackEntrySnapshot]
}
#endif
