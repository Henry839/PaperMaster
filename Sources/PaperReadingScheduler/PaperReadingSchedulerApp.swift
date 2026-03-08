import SwiftUI

@main
struct PaperReadingSchedulerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var services = AppServices.live()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(services)
                .environment(router)
                .task {
                    appDelegate.router = router
                }
        }
        .modelContainer(for: [Paper.self, Tag.self, UserSettings.self, FeedbackEntry.self])
        .defaultSize(width: 1320, height: 860)
    }
}
