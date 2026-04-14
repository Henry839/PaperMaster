#if PAPERMASTER_LEGACY_MODE
import Foundation

struct PersistentStoreSetup {
    let container: ModelContainer
    let startupNoticeMessage: String?
    let startupErrorMessage: String?
    let storeURL: URL?
}

struct PersistentStoreController {
    private let fileManager: FileManager
    let applicationSupportDirectoryURL: URL

    init(
        fileManager: FileManager = .default,
        applicationSupportDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    var storeDirectoryURL: URL {
        applicationSupportDirectoryURL.appendingPathComponent("PaperMaster", isDirectory: true)
    }

    var currentStoreURL: URL {
        storeDirectoryURL.appendingPathComponent("PaperMaster.library.json")
    }

    func makeLaunchSetup() -> PersistentStoreSetup {
        do {
            try fileManager.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)
            let store = try LegacyLibraryStore.load(from: currentStoreURL, fileManager: fileManager)
            return PersistentStoreSetup(
                container: ModelContainer(store: store),
                startupNoticeMessage: nil,
                startupErrorMessage: nil,
                storeURL: currentStoreURL
            )
        } catch {
            return PersistentStoreSetup(
                container: ModelContainer(store: .inMemory()),
                startupNoticeMessage: nil,
                startupErrorMessage: "PaperMaster could not open its local library. The app started with a temporary empty session. \(error.localizedDescription)",
                storeURL: nil
            )
        }
    }
}
#endif
