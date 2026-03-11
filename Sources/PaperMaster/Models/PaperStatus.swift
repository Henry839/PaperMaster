import Foundation

enum PaperStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case inbox
    case scheduled
    case reading
    case done
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox:
            "Inbox"
        case .scheduled:
            "Scheduled"
        case .reading:
            "Reading"
        case .done:
            "Done"
        case .archived:
            "Archived"
        }
    }

    var isActiveQueue: Bool {
        switch self {
        case .scheduled, .reading:
            true
        case .inbox, .done, .archived:
            false
        }
    }
}
