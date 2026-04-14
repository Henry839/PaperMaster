import SwiftUI

#if PAPERMASTER_COMPATIBILITY_APP
@main
struct PaperMasterApp: App {
    var body: some Scene {
        WindowGroup {
            LegacyCompatibilityRootView()
                .frame(minWidth: 720, minHeight: 460)
        }
        .defaultSize(width: 860, height: 520)
        .windowToolbarStyle(.unified)
    }
}

private struct LegacyCompatibilityRootView: View {
    @Environment(\.openURL) private var openURL

    private let systemVersion = ProcessInfo.processInfo.operatingSystemVersionString

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("PaperMaster Compatibility Mode")
                .font(.system(size: 30, weight: .semibold))

            Text("This macOS 13 build launches a reduced compatibility app so the project can run locally without upgrading the operating system.")
                .font(.title3)
                .foregroundStyle(.secondary)

            GroupBox("Why the full app is unavailable on this Mac") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The main PaperMaster app depends on SwiftData and Observation-based app state that require macOS 14 or newer.")
                    Text("Current system: \(systemVersion)")
                    Text("You can still use this compatibility build to verify the package, scripts, and app bundle launch path on macOS 13.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button("Open Project Folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
                }

                Button("Open SwiftData Docs") {
                    guard let url = URL(string: "https://developer.apple.com/documentation/swiftdata") else { return }
                    openURL(url)
                }
            }

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
#endif
