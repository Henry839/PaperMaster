import Foundation
#if PAPERMASTER_LEGACY_MODE
import Combine
#else
import SwiftData
#endif

#if PAPERMASTER_LEGACY_MODE
final class Tag: ObservableObject {
    @Published var name: String
    weak var paper: Paper?

    init(name: String, paper: Paper? = nil) {
        self.name = Tag.normalize(name)
        self.paper = paper
    }

    convenience init(snapshot: TagSnapshot) {
        self.init(name: snapshot.name)
    }

    var snapshot: TagSnapshot {
        TagSnapshot(name: name)
    }

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func displayName(for value: String) -> String {
        normalize(value).replacingOccurrences(of: "-", with: " ")
    }

    var displayName: String {
        Tag.displayName(for: name)
    }

    static func buildList(from names: [String]) -> [Tag] {
        Array(Set(names.map(Tag.normalize).filter { !$0.isEmpty }))
            .sorted()
            .map { Tag(name: $0) }
    }
}

struct TagSnapshot: Codable {
    let name: String
}
#else
@Model
final class Tag {
    var name: String
    var paper: Paper?

    init(name: String, paper: Paper? = nil) {
        self.name = Tag.normalize(name)
        self.paper = paper
    }

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func displayName(for value: String) -> String {
        normalize(value).replacingOccurrences(of: "-", with: " ")
    }

    var displayName: String {
        Tag.displayName(for: name)
    }

    static func buildList(from names: [String]) -> [Tag] {
        Array(Set(names.map(Tag.normalize).filter { !$0.isEmpty }))
            .sorted()
            .map { Tag(name: $0) }
    }
}
#endif
