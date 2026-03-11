import Foundation

enum ImportBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    case scheduleImmediately
    case addToInbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scheduleImmediately:
            "Schedule Immediately"
        case .addToInbox:
            "Add To Inbox"
        }
    }
}
