import SwiftData
import SwiftUI

@main
struct PaperMasterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var services: AppServices
    @State private var router = AppRouter()
    private let modelContainer: ModelContainer

    init() {
        let setup = PersistentStoreController().makeLaunchSetup()
        self.modelContainer = setup.container
        _services = State(
            initialValue: AppServices.live(
                startupNoticeMessage: setup.startupNoticeMessage,
                startupErrorMessage: setup.startupErrorMessage
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(services)
                .environment(router)
                .task {
                    appDelegate.router = router
                }
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1320, height: 860)
    }
}
