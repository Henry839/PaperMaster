import Foundation

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
    var sourceURL: URL?
    var pdfURL: URL?
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
            sourceURL: url,
            pdfURL: nil
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
            sourceURL: sourceURL,
            pdfURL: pdfURL
        )
    }

    private func fallbackMetadata(for url: URL) -> ResolvedPaperMetadata {
        ResolvedPaperMetadata(
            title: inferredTitle(from: url),
            authors: [],
            abstractText: "",
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

private struct ArXivEntry {
    var title: String = ""
    var authors: [String] = []
    var summary: String = ""
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

        guard isInsideEntry else { return }

        if isInsideAuthor, elementName == "name", !text.isEmpty {
            currentAuthorName = text
        }

        switch elementName {
        case "title":
            if entry.title.isEmpty, !text.isEmpty {
                entry.title = text
            }
        case "summary":
            if entry.summary.isEmpty, !text.isEmpty {
                entry.summary = text
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
