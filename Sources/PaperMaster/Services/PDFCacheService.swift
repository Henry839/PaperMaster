import Foundation

protocol FileManaging: Sendable {
    func createDirectory(at url: URL, withIntermediateDirectories: Bool, attributes: [FileAttributeKey: Any]?) throws
    func removeItem(at url: URL) throws
    func fileExists(atPath path: String) -> Bool
}

extension FileManager: FileManaging {}

struct PDFCacheService: Sendable {
    let networking: Networking
    let fileManager: FileManaging
    let cacheDirectoryURL: URL

    init(
        networking: Networking = URLSessionNetworking(),
        fileManager: FileManaging = FileManager.default,
        cacheDirectoryURL: URL? = nil
    ) {
        self.networking = networking
        self.fileManager = fileManager
        let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PaperMaster", isDirectory: true)
            .appendingPathComponent("PDFCache", isDirectory: true)
        self.cacheDirectoryURL = cacheDirectoryURL ?? defaultDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PaperMaster-PDFCache", isDirectory: true)
    }

    @MainActor
    func cachePDF(for paper: Paper) async throws -> URL {
        guard let pdfURL = paper.pdfURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        let filename = suggestedFilename(for: paper.title, fallback: paper.id.uuidString)
        let destination = try await cachePDF(from: pdfURL, suggestedFilename: filename)
        paper.cachedPDFURL = destination
        return destination
    }

    func cachePDF(from url: URL, suggestedFilename: String) async throws -> URL {
        try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        let filename = suggestedFilename.hasSuffix(".pdf") ? suggestedFilename : "\(suggestedFilename).pdf"
        let destination = cacheDirectoryURL.appendingPathComponent(filename)
        let (data, _) = try await networking.data(from: url)
        try data.write(to: destination, options: [.atomic])
        return destination
    }

    @MainActor
    func removeCachedPDF(for paper: Paper) throws {
        guard let cachedURL = paper.cachedPDFURL else { return }
        if fileManager.fileExists(atPath: cachedURL.path) {
            try fileManager.removeItem(at: cachedURL)
        }
        paper.cachedPDFURL = nil
    }

    func suggestedFilename(for title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? fallback : trimmed
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let cleaned = base.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }
        .joined()

        return cleaned
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "--", with: "-")
            .lowercased()
    }
}
