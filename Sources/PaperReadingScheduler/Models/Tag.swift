import Foundation
import SwiftData

@Model
final class Tag {
    @Attribute(.unique) var name: String

    init(name: String) {
        self.name = Tag.normalize(name)
    }

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var displayName: String {
        name.replacingOccurrences(of: "-", with: " ")
    }
}
