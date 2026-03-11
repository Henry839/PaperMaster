import Foundation
import Observation

struct ReaderPresentation: Identifiable {
    let id = UUID()
    let paperID: UUID
    let title: String
    let fileURL: URL
}

@MainActor
@Observable
final class AppRouter {
    var selectedScreen: AppScreen = .today
    var selectedPaperID: UUID?
    var isImportSheetPresented = false
    var isFeedbackSheetPresented = false
    var readerPresentation: ReaderPresentation?

    func handleNotification(userInfo: [AnyHashable: Any]) {
        if let destination = userInfo["destination"] as? String, destination == "today" {
            selectedScreen = .today
            return
        }

        if let paperIDString = userInfo["paperID"] as? String,
           let paperID = UUID(uuidString: paperIDString) {
            selectedScreen = .today
            selectedPaperID = paperID
        }
    }
}
