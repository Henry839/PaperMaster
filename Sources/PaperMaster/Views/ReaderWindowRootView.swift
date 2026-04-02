import SwiftData
import SwiftUI

#if os(macOS)
struct ReaderWindowRootView: View {
    let paperID: UUID?
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router

    @Query(sort: \Paper.dateAdded, order: .reverse) private var papers: [Paper]
    @Query private var settingsList: [UserSettings]

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
#endif

#if os(iOS)
struct IPadReaderRootView: View {
    let presentation: ReaderPresentation
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Query(sort: \Paper.dateAdded, order: .reverse) private var papers: [Paper]
    @Query private var settingsList: [UserSettings]

    private var settings: UserSettings? {
        settingsList.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let paper = papers.first(where: { $0.id == presentation.paperID }),
                   let settings {
                    ReaderView(paper: paper, fileURL: presentation.fileURL, settings: settings)
                } else {
                    ContentUnavailableView(
                        "Paper unavailable",
                        systemImage: "doc.slash",
                        description: Text("This paper is no longer available in the local library.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            if router.readerPresentation?.id == presentation.id {
                router.readerPresentation = nil
            }
        }
    }
}
#endif
