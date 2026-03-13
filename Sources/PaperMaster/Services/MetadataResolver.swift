import Foundation
import PDFKit

protocol Networking: Sendable {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

struct URLSessionNetworking: Networking {
    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(from: url)
    }
}

struct ResolvedPaperMetadata: Sendable {
    var title: String
    var authors: [String]
    var abstractText: String
    var arxivID: String?
    var doi: String?
    var publishedYear: Int?
    var sourceURL: URL?
    var pdfURL: URL?

    init(
        title: String,
        authors: [String],
        abstractText: String,
        arxivID: String? = nil,
        doi: String? = nil,
        publishedYear: Int? = nil,
        sourceURL: URL?,
        pdfURL: URL?
    ) {
        self.title = title
        self.authors = authors
        self.abstractText = abstractText
        self.arxivID = arxivID
        self.doi = doi
        self.publishedYear = publishedYear
        self.sourceURL = sourceURL
        self.pdfURL = pdfURL
    }
}

enum MetadataResolverError: LocalizedError {
    case unsupportedURL
    case invalidServerResponse
    case missingEntry

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            "The paper URL could not be interpreted."
        case .invalidServerResponse:
            "The metadata server returned an invalid response."
        case .missingEntry:
            "No paper metadata was found for that URL."
        }
    }
}

protocol MetadataResolving: Sendable {
    func resolve(url: URL) async throws -> ResolvedPaperMetadata
}

struct MetadataResolver: MetadataResolving {
    let networking: Networking

    init(networking: Networking = URLSessionNetworking()) {
        self.networking = networking
    }

    func resolve(url: URL) async throws -> ResolvedPaperMetadata {
        if url.isFileURL, url.isLikelyPDF {
            return try await resolveLocalPDF(at: url)
        }

        if let arxivID = url.arxivIdentifier {
            return try await resolveArXiv(id: arxivID)
        }

        if url.isLikelyPDF {
            return fallbackMetadata(for: url)
        }

        return ResolvedPaperMetadata(
            title: inferredTitle(from: url),
            authors: [],
            abstractText: "",
            arxivID: nil,
            doi: nil,
            publishedYear: nil,
            sourceURL: url,
            pdfURL: nil
        )
    }

    private func resolveLocalPDF(at fileURL: URL) async throws -> ResolvedPaperMetadata {
        let extracted = LocalPDFMetadataExtractor().extract(from: fileURL)

        if let arxivID = extracted.arxivID,
           let arxivResolved = try? await resolveArXiv(id: arxivID) {
            return ResolvedPaperMetadata(
                title: arxivResolved.title,
                authors: arxivResolved.authors,
                abstractText: extracted.abstractText.isEmpty ? arxivResolved.abstractText : extracted.abstractText,
                arxivID: arxivResolved.arxivID,
                doi: extracted.doi ?? arxivResolved.doi,
                publishedYear: extracted.publishedYear ?? arxivResolved.publishedYear,
                sourceURL: arxivResolved.sourceURL,
                pdfURL: fileURL
            )
        }

        let title = extracted.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ResolvedPaperMetadata(
            title: title.isEmpty ? inferredTitle(from: fileURL) : title,
            authors: extracted.authors,
            abstractText: extracted.abstractText,
            arxivID: extracted.arxivID,
            doi: extracted.doi,
            publishedYear: extracted.publishedYear,
            sourceURL: fileURL,
            pdfURL: fileURL
        )
    }

    private func resolveArXiv(id: String) async throws -> ResolvedPaperMetadata {
        guard var components = URLComponents(string: "https://export.arxiv.org/api/query") else {
            throw MetadataResolverError.unsupportedURL
        }
        components.queryItems = [
            URLQueryItem(name: "id_list", value: id)
        ]

        guard let apiURL = components.url else {
            throw MetadataResolverError.unsupportedURL
        }

        let (data, response) = try await networking.data(from: apiURL)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw MetadataResolverError.invalidServerResponse
        }

        let entry = try ArXivMetadataParser().parse(data: data)
        guard !entry.title.isEmpty else {
            throw MetadataResolverError.missingEntry
        }

        let sourceURL = URL(string: "https://arxiv.org/abs/\(id)")
        let pdfURL = entry.pdfURL ?? URL(string: "https://arxiv.org/pdf/\(id).pdf")
        return ResolvedPaperMetadata(
            title: entry.title,
            authors: entry.authors,
            abstractText: entry.summary,
            arxivID: id,
            doi: entry.doi,
            publishedYear: entry.publishedYear,
            sourceURL: sourceURL,
            pdfURL: pdfURL
        )
    }

    private func fallbackMetadata(for url: URL) -> ResolvedPaperMetadata {
        ResolvedPaperMetadata(
            title: inferredTitle(from: url),
            authors: [],
            abstractText: "",
            arxivID: url.arxivIdentifier,
            doi: nil,
            publishedYear: nil,
            sourceURL: url,
            pdfURL: url
        )
    }

    private func inferredTitle(from url: URL) -> String {
        let filename = url.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        let cleaned = filename
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? url.host ?? "Untitled Paper" : cleaned
    }
}

private struct LocalPDFMetadataExtractor {
    func extract(from fileURL: URL) -> LocalPDFExtractedMetadata {
        guard let document = PDFDocument(url: fileURL) else {
            return LocalPDFExtractedMetadata()
        }

        let documentAttributes = document.documentAttributes ?? [:]
        let titleFromAttributes = (documentAttributes[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let authorsFromAttributes = parseAuthors(from: documentAttributes[PDFDocumentAttribute.authorAttribute] as? String)

        let firstPagesText = (0..<min(document.pageCount, 3))
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        let normalizedText = firstPagesText.replacingOccurrences(of: "\u{00A0}", with: " ")
        let lines = normalizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        let heuristicTitle = inferTitle(from: lines)
        let heuristicAuthors = inferAuthors(from: lines, title: heuristicTitle)

        return LocalPDFExtractedMetadata(
            title: normalizedPreferredTitle(titleFromAttributes, fallback: heuristicTitle),
            authors: authorsFromAttributes.isEmpty ? heuristicAuthors : authorsFromAttributes,
            abstractText: extractAbstract(from: normalizedText),
            arxivID: firstMatch(in: normalizedText, pattern: #"(?:arXiv:\s*|https?://arxiv\.org/(?:abs|pdf)/)([A-Za-z\-\.]*\d{4}\.\d{4,5}(?:v\d+)?)"#),
            doi: firstMatch(in: normalizedText, pattern: #"(10\.\d{4,9}/[-._;()/:A-Z0-9]+)"#, options: [.caseInsensitive]),
            publishedYear: inferPublishedYear(from: normalizedText)
        )
    }

    private func normalizedPreferredTitle(_ title: String?, fallback: String) -> String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmedTitle.isEmpty == false else { return fallback }

        let lowercased = trimmedTitle.lowercased()
        if lowercased.hasSuffix(".pdf") || lowercased.hasPrefix("microsoft word") {
            return fallback
        }

        return trimmedTitle
    }

    private func inferTitle(from lines: [String]) -> String {
        let candidates = lines
            .filter { line in
                line.count >= 12 &&
                line.count <= 220 &&
                line.range(of: #"^(abstract|arxiv|submitted|accepted|proceedings)"#, options: [.regularExpression, .caseInsensitive]) == nil
            }

        return candidates.first ?? ""
    }

    private func inferAuthors(from lines: [String], title: String) -> [String] {
        guard let titleIndex = lines.firstIndex(where: { $0 == title }) else { return [] }

        for line in lines.dropFirst(titleIndex + 1).prefix(4) {
            let authors = parseAuthors(from: line)
            if authors.isEmpty == false {
                return authors
            }
        }

        return []
    }

    private func parseAuthors(from rawValue: String?) -> [String] {
        guard let rawValue else { return [] }
        let cleaned = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: " and ", with: ", ", options: .caseInsensitive)
        return cleaned
            .split(separator: ",")
            .map { fragment in
                fragment
                    .replacingOccurrences(of: #"\d"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { $0.count >= 3 && $0.contains(" ") }
    }

    private func extractAbstract(from text: String) -> String {
        guard let range = text.range(
            of: #"(?is)\babstract\b[:\s]*(.+?)(?:\n\s*(?:1[\.\s]+introduction|introduction)\b|$)"#,
            options: .regularExpression
        ) else {
            return ""
        }

        let raw = String(text[range])
            .replacingOccurrences(of: #"(?is)^\s*abstract\b[:\s]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.count > 2_000 ? String(raw.prefix(2_000)) : raw
    }

    private func inferPublishedYear(from text: String) -> Int? {
        guard let yearString = firstMatch(in: text, pattern: #"\b(19|20)\d{2}\b"#),
              let year = Int(yearString) else {
            return nil
        }
        return year
    }

    private func firstMatch(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
        guard let swiftRange = Range(captureRange, in: text) else {
            return nil
        }

        return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct LocalPDFExtractedMetadata {
    var title: String = ""
    var authors: [String] = []
    var abstractText: String = ""
    var arxivID: String?
    var doi: String?
    var publishedYear: Int?
}

private struct ArXivEntry {
    var title: String = ""
    var authors: [String] = []
    var summary: String = ""
    var doi: String?
    var publishedYear: Int?
    var pdfURL: URL?
}

private final class ArXivMetadataParser: NSObject, XMLParserDelegate {
    private var entry = ArXivEntry()
    private var currentValue = ""
    private var isInsideEntry = false
    private var isInsideAuthor = false
    private var currentAuthorName = ""
    private var didParseEntry = false

    func parse(data: Data) throws -> ArXivEntry {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? MetadataResolverError.invalidServerResponse
        }
        return entry
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentValue = ""

        if elementName == "entry", didParseEntry == false {
            isInsideEntry = true
            return
        }

        guard isInsideEntry else { return }

        if elementName == "author" {
            isInsideAuthor = true
            currentAuthorName = ""
        }

        if elementName == "link",
           let href = attributeDict["href"],
           attributeDict["title"]?.lowercased().contains("pdf") == true {
            entry.pdfURL = URL(string: href)
        }

        if elementName == "link",
           entry.pdfURL == nil,
           let href = attributeDict["href"],
           attributeDict["type"]?.lowercased() == "application/pdf" {
            entry.pdfURL = URL(string: href)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = currentValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedElementName = normalizedElementName(elementName: elementName, qualifiedName: qName)

        guard isInsideEntry else { return }

        if isInsideAuthor, normalizedElementName == "name", !text.isEmpty {
            currentAuthorName = text
        }

        switch normalizedElementName {
        case "title":
            if entry.title.isEmpty, !text.isEmpty {
                entry.title = text
            }
        case "summary":
            if entry.summary.isEmpty, !text.isEmpty {
                entry.summary = text
            }
        case "doi":
            if entry.doi == nil, !text.isEmpty {
                entry.doi = text
            }
        case "published":
            if entry.publishedYear == nil,
               let publishedAt = ISO8601DateFormatter().date(from: text) {
                entry.publishedYear = Calendar(identifier: .gregorian).component(.year, from: publishedAt)
            }
        case "author":
            if !currentAuthorName.isEmpty {
                entry.authors.append(currentAuthorName)
            }
            isInsideAuthor = false
            currentAuthorName = ""
        case "entry":
            isInsideEntry = false
            didParseEntry = true
        default:
            break
        }

        currentValue = ""
    }

    private func normalizedElementName(elementName: String, qualifiedName: String?) -> String {
        let candidate = qualifiedName ?? elementName
        return candidate.components(separatedBy: ":").last?.lowercased() ?? candidate.lowercased()
    }
}

extension URL {
    var arxivIdentifier: String? {
        guard let host else { return nil }
        let normalizedHost = host.lowercased()
        guard normalizedHost.contains("arxiv.org") else { return nil }

        let components = pathComponents.filter { $0 != "/" }
        guard components.count >= 2 else { return nil }

        if components[0] == "abs" {
            return components[1]
        }

        if components[0] == "pdf" {
            return components[1].replacingOccurrences(of: ".pdf", with: "")
        }

        return nil
    }

    var isLikelyPDF: Bool {
        pathExtension.lowercased() == "pdf"
    }

    var arxivAbstractURL: URL? {
        guard let identifier = arxivIdentifier else { return nil }
        return URL(string: "https://arxiv.org/abs/\(identifier)")
    }

    var canonicalArxivIdentifier: String? {
        guard let arxivIdentifier else { return nil }

        let lowercasedIdentifier = arxivIdentifier.lowercased()
        guard let versionRange = lowercasedIdentifier.range(
            of: #"v\d+$"#,
            options: .regularExpression
        ) else {
            return lowercasedIdentifier
        }

        return String(lowercasedIdentifier[..<versionRange.lowerBound])
    }

    var canonicalPaperIdentityKeys: Set<String> {
        var keys: Set<String> = []

        if let canonicalURLString = canonicalPaperURLString {
            keys.insert("url:\(canonicalURLString)")
        }

        if let canonicalArxivIdentifier {
            keys.insert("arxiv:\(canonicalArxivIdentifier)")
        }

        return keys
    }

    private var canonicalPaperURLString: String? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()

        var normalizedPath = components.percentEncodedPath
        if normalizedPath.count > 1, normalizedPath.hasSuffix("/") {
            normalizedPath.removeLast()
        }
        components.percentEncodedPath = normalizedPath

        if components.queryItems?.isEmpty == true {
            components.query = nil
        }

        return components.string
    }
}
