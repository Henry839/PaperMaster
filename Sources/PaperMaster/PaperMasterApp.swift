import SwiftData
import SwiftUI

@main
struct PaperMasterApp: App {
    static let mainWindowID = "main"
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
        WindowGroup(id: Self.mainWindowID, makeContent: {
            MainWindowRootView(
                appDelegate: appDelegate,
                services: services,
                router: router
            )
        })
        .modelContainer(modelContainer)
        .defaultSize(width: 1320, height: 860)
    }
}

private struct MainWindowRootView: View {
    @Environment(\.openWindow) private var openWindow

    let appDelegate: AppDelegate
    let services: AppServices
    let router: AppRouter

    var body: some View {
        AppRootView()
            .environment(services)
            .environment(router)
            .onAppear {
                appDelegate.router = router
                appDelegate.reopenMainWindow = {
                    openWindow(id: PaperMasterApp.mainWindowID)
                }
            }
    }
}
