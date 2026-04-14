import Combine
import Foundation

struct ReaderPresentation: Identifiable {
    let id = UUID()
    let paperID: UUID
    let title: String
    let fileURL: URL
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedScreen: AppScreen = .today
    @Published var selectedPaperID: UUID?
    @Published var isImportSheetPresented = false
    @Published var isFeedbackSheetPresented = false
    @Published var readerPresentation: ReaderPresentation?

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
