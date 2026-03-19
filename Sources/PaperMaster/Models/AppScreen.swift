import Foundation

enum AppScreen: String, CaseIterable, Identifiable {
    case today
    case inbox
    case queue
    case library
    case hot
    case fusionReactor
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            "Today"
        case .inbox:
            "Inbox"
        case .queue:
            "Queue"
        case .library:
            "Library"
        case .hot:
            "Hot Papers"
        case .fusionReactor:
            "Paper Fusion Reactor"
        case .settings:
            "Settings"
        }
    }

    var sidebarTitle: String {
        switch self {
        case .hot:
            "Hot"
        case .fusionReactor:
            "Fusion Reactor"
        default:
            title
        }
    }

    var symbolName: String {
        switch self {
        case .today:
            "sun.max"
        case .inbox:
            "tray.full"
        case .queue:
            "list.number"
        case .library:
            "books.vertical"
        case .hot:
            "sparkles.rectangle.stack"
        case .fusionReactor:
            "flame"
        case .settings:
            "gearshape"
        }
    }
}
