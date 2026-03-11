import AppKit
@preconcurrency import UserNotifications

struct AppDockReopenCoordinator {
    struct WindowTarget {
        let isVisible: Bool
        let restore: @MainActor @Sendable () -> Void
    }

    let windowTargets: () -> [WindowTarget]
    let reopenMainWindow: (@MainActor @Sendable () -> Void)?
    let activateApp: @MainActor @Sendable () -> Void

    @MainActor
    @discardableResult
    func handleReopen(hasVisibleWindows: Bool) -> Bool {
        guard hasVisibleWindows == false else {
            return false
        }

        if let windowTarget = windowTargets().first(where: { $0.isVisible == false }) {
            windowTarget.restore()
            activateApp()
            return true
        }

        guard let reopenMainWindow else {
            return false
        }

        reopenMainWindow()
        activateApp()
        return true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var router: AppRouter?
    var reopenMainWindow: (@MainActor @Sendable () -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopenCoordinator(for: sender).handleReopen(hasVisibleWindows: flag)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        completionHandler()

        Task { @MainActor [weak self] in
            self?.router?.handleNotification(userInfo: userInfo)
        }
    }

    func reopenCoordinator(for application: NSApplication) -> AppDockReopenCoordinator {
        AppDockReopenCoordinator(
            windowTargets: { [weak application] in
                guard let application else {
                    return []
                }

                return application.windows
                    .filter(Self.isStandardWindow)
                    .map { window in
                        AppDockReopenCoordinator.WindowTarget(
                            isVisible: window.isVisible,
                            restore: {
                                if window.isMiniaturized {
                                    window.deminiaturize(nil)
                                }
                                window.makeKeyAndOrderFront(nil)
                            }
                        )
                    }
            },
            reopenMainWindow: reopenMainWindow,
            activateApp: { [weak application] in
                application?.activate(ignoringOtherApps: true)
            }
        )
    }

    private static func isStandardWindow(_ window: NSWindow) -> Bool {
        window.isExcludedFromWindowsMenu == false &&
        window.canBecomeMain &&
        (window is NSPanel) == false
    }
}
