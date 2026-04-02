import SwiftData
import SwiftUI

enum PaperMasterSceneID {
    static let main = "main"
    static let reader = "reader"
}

#if os(macOS)
public struct PaperMasterMacScene: Scene {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var services: AppServices
    @State private var agentRuntime = AgentRuntimeService()
    @State private var router = AppRouter()
    private let modelContainer: ModelContainer

    public init() {
        let setup = PersistentStoreController().makeLaunchSetup()
        self.modelContainer = setup.container
        _services = State(
            initialValue: AppServices.live(
                startupNoticeMessage: setup.startupNoticeMessage,
                startupErrorMessage: setup.startupErrorMessage
            )
        )
    }

    public var body: some Scene {
        WindowGroup(id: PaperMasterSceneID.main, makeContent: {
            PaperMasterMainSceneRootView(
                appDelegate: appDelegate,
                services: services,
                agentRuntime: agentRuntime,
                router: router
            )
        })
        .modelContainer(modelContainer)
        .defaultSize(width: 1320, height: 860)

        WindowGroup(id: PaperMasterSceneID.reader, for: UUID.self) { $paperID in
            ReaderWindowRootView(paperID: paperID)
                .environment(services)
                .environment(router)
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1280, height: 900)
        .windowToolbarStyle(.unified)
    }
}
#endif

#if os(iOS)
public struct PaperMasterIPadScene: Scene {
    @State private var services: AppServices
    @State private var agentRuntime = AgentRuntimeService()
    @State private var router = AppRouter()
    private let modelContainer: ModelContainer

    public init() {
        let setup = PersistentStoreController().makeLaunchSetup()
        self.modelContainer = setup.container
        _services = State(
            initialValue: AppServices.live(
                startupNoticeMessage: setup.startupNoticeMessage,
                startupErrorMessage: setup.startupErrorMessage
            )
        )
    }

    public var body: some Scene {
        WindowGroup {
            PaperMasterMainSceneRootView(
                services: services,
                agentRuntime: agentRuntime,
                router: router
            )
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1194, height: 834)
    }
}
#endif

private struct PaperMasterMainSceneRootView: View {
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    let appDelegate: AppDelegate
    #endif

    let services: AppServices
    let agentRuntime: AgentRuntimeService
    let router: AppRouter

    var body: some View {
        AppRootView()
            .environment(services)
            .environment(agentRuntime)
            .environment(router)
            .onAppear {
                #if os(macOS)
                appDelegate.router = router
                appDelegate.reopenMainWindow = {
                    openWindow(id: PaperMasterSceneID.main)
                }
                #endif
            }
    }
}
