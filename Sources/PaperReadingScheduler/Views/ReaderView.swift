import PDFKit
import SwiftUI

struct ReaderView: View {
    let presentation: ReaderPresentation

    var body: some View {
        PDFDocumentView(url: presentation.fileURL)
            .navigationTitle(presentation.title)
            .frame(minWidth: 900, minHeight: 700)
    }
}

private struct PDFDocumentView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(url: url)
    }
}
