#if !PAPERMASTER_LEGACY_MODE
import SwiftData
#endif
import SwiftUI

@main
struct PaperMasterApp: App {
    static let mainWindowID = "main"
    static let readerWindowID = "reader"
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var services: AppServices
    @StateObject private var agentRuntime = AgentRuntimeService()
    @StateObject private var router = AppRouter()
    private let modelContainer: ModelContainer

    init() {
        let setup = PersistentStoreController().makeLaunchSetup()
        self.modelContainer = setup.container
        _services = StateObject(
            wrappedValue: AppServices.live(
                startupNoticeMessage: setup.startupNoticeMessage,
                startupErrorMessage: setup.startupErrorMessage
            )
        )
    }

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            #if PAPERMASTER_LEGACY_MODE
            MainWindowRootView(
                appDelegate: appDelegate,
                services: services,
                agentRuntime: agentRuntime,
                router: router
            )
            .environmentObject(modelContainer.store)
            #else
            MainWindowRootView(
                appDelegate: appDelegate,
                services: services,
                agentRuntime: agentRuntime,
                router: router
            )
            #endif
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1320, height: 860)

        WindowGroup(id: Self.readerWindowID, for: UUID.self) { $paperID in
            #if PAPERMASTER_LEGACY_MODE
            ReaderWindowRootView(paperID: paperID)
                .environmentObject(modelContainer.store)
                .environmentObject(services)
                .environmentObject(router)
            #else
            ReaderWindowRootView(paperID: paperID)
                .environmentObject(services)
                .environmentObject(router)
            #endif
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1280, height: 900)
        .windowToolbarStyle(.unified)
    }
}

private struct MainWindowRootView: View {
    @Environment(\.openWindow) private var openWindow

    let appDelegate: AppDelegate
    let services: AppServices
    let agentRuntime: AgentRuntimeService
    let router: AppRouter

    var body: some View {
        AppRootView()
            .environmentObject(services)
            .environmentObject(agentRuntime)
            .environmentObject(router)
            .onAppear {
                appDelegate.router = router
                appDelegate.reopenMainWindow = {
                    openWindow(id: PaperMasterApp.mainWindowID)
                }
            }
    }
}
