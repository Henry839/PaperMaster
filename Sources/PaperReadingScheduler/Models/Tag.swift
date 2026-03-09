import Foundation
import SwiftData

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
