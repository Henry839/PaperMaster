#if !PAPERMASTER_LEGACY_MODE
import SwiftData
#endif
import SwiftUI

struct ReaderWindowRootView: View {
    let paperID: UUID?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var router: AppRouter
#if PAPERMASTER_LEGACY_MODE
    @EnvironmentObject private var libraryStore: LegacyLibraryStore
#else
    @Query(sort: \Paper.dateAdded, order: .reverse) private var papers: [Paper]
    @Query private var settingsList: [UserSettings]
#endif

#if PAPERMASTER_LEGACY_MODE
    private var papers: [Paper] {
        libraryStore.papers.sorted { $0.dateAdded > $1.dateAdded }
    }

    private var settingsList: [UserSettings] {
        libraryStore.settingsList
    }
#endif

    private var settings: UserSettings? {
        settingsList.first
    }

    var body: some View {
        Group {
            if let paperID,
               let paper = papers.first(where: { $0.id == paperID }),
               let presentation = router.readerPresentation,
               presentation.paperID == paperID,
               let settings {
                ReaderView(paper: paper, fileURL: presentation.fileURL, settings: settings)
            } else if paperID != nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Paper unavailable",
                    systemImage: "doc.slash",
                    description: Text("This paper is no longer available in the local library.")
                )
            }
        }
        .onDisappear {
            if let paperID, router.readerPresentation?.paperID == paperID {
                router.readerPresentation = nil
            }
        }
    }
}
