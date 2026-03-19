import Foundation

protocol HotPaperDiscovering: Sendable {
    func discoverPapers(in category: HotPaperCategory, librarySignals: [String]) async throws -> [HotPaper]
}

enum HotPaperDiscoveryError: LocalizedError {
    case invalidFeedURL
    case invalidServerResponse

    var errorDescription: String? {
        switch self {
        case .invalidFeedURL:
            "The hot paper feed URL could not be created."
        case .invalidServerResponse:
            "The hot paper feed returned an invalid response."
        }
    }
}

struct ArXivHotPaperDiscoveryService: HotPaperDiscovering {
    let networking: HTTPNetworking
    let now: @Sendable () -> Date

    init(
        networking: HTTPNetworking = URLSessionHTTPNetworking(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.networking = networking
        self.now = now
    }

    func discoverPapers(in category: HotPaperCategory, librarySignals: [String]) async throws -> [HotPaper] {
        guard let feedURL = feedURL(for: category) else {
            throw HotPaperDiscoveryError.invalidFeedURL
        }

        var request = URLRequest(url: feedURL)
        request.setValue("application/atom+xml, application/xml;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await networking.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw HotPaperDiscoveryError.invalidServerResponse
        }

        let entries = try ArXivHotPaperFeedParser().parse(data: data)
        return score(entries: entries, category: category, librarySignals: librarySignals)
    }

    private func feedURL(for category: HotPaperCategory) -> URL? {
        var components = URLComponents(string: "https://export.arxiv.org/api/query")
        components?.queryItems = [
            URLQueryItem(name: "search_query", value: "cat:\(category.arxivQueryValue)"),
            URLQueryItem(name: "sortBy", value: "submittedDate"),
            URLQueryItem(name: "sortOrder", value: "descending"),
            URLQueryItem(name: "max_results", value: "18")
        ]
        return components?.url
    }

    private func score(entries: [ArXivHotPaperEntry], category: HotPaperCategory, librarySignals: [String]) -> [HotPaper] {
        let referenceDate = now()
        let normalizedLibrarySignals = normalizedTokens(from: librarySignals)

        return entries
            .map { entry in
                let ageInDays = max(0, referenceDate.timeIntervalSince(entry.publishedAt) / 86_400)
                let freshnessScore = max(0, 1 - min(ageInDays, 21) / 21)

                let entryTokens = normalizedTokens(
                    from: [entry.title, entry.summary, entry.primaryCategory, category.title]
                )
                let overlapCount = entryTokens.intersection(normalizedLibrarySignals).count
                let overlapScore = min(Double(overlapCount), 4) / 4
                let score = (freshnessScore * 0.72) + (overlapScore * 0.28)

                return HotPaper(
                    id: entry.id,
                    title: entry.title,
                    authors: entry.authors,
                    summary: entry.summary,
                    primaryCategory: entry.primaryCategory,
                    publishedAt: entry.publishedAt,
                    updatedAt: entry.updatedAt,
                    sourceURL: entry.sourceURL,
                    pdfURL: entry.pdfURL,
                    score: score,
                    scoreLabel: scoreLabel(for: score),
                    reasons: reasonBadges(
                        for: entry,
                        category: category,
                        ageInDays: ageInDays,
                        overlapCount: overlapCount
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.publishedAt > rhs.publishedAt
            }
    }

    private func reasonBadges(
        for entry: ArXivHotPaperEntry,
        category: HotPaperCategory,
        ageInDays: Double,
        overlapCount: Int
    ) -> [String] {
        var badges: [String] = [category.title]

        if ageInDays <= 3 {
            badges.append("New this week")
        } else if ageInDays <= 7 {
            badges.append("Fresh")
        }

        if overlapCount > 0 {
            badges.append("\(overlapCount)x library match")
        }

        if entry.primaryCategory.isEmpty == false, entry.primaryCategory != category.arxivQueryValue {
            badges.append(entry.primaryCategory)
        }

        return Array(badges.prefix(3))
    }

    private func scoreLabel(for score: Double) -> String {
        switch score {
        case 0.8...:
            "Very hot"
        case 0.6...:
            "Rising"
        default:
            "Fresh pick"
        }
    }

    private func normalizedTokens(from strings: [String]) -> Set<String> {
        let stopWords: Set<String> = [
            "paper", "using", "with", "from", "into", "over", "under", "towards",
            "based", "learning", "model", "models", "large", "language", "vision",
            "for", "and", "the", "that", "this", "into", "without"
        ]

        return Set(
            strings
                .flatMap { value in
                    value.lowercased()
                        .components(separatedBy: CharacterSet.alphanumerics.inverted)
                }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 3 && stopWords.contains($0) == false }
        )
    }
}

private struct ArXivHotPaperEntry: Sendable {
    let id: String
    let title: String
    let summary: String
    let authors: [String]
    let primaryCategory: String
    let publishedAt: Date
    let updatedAt: Date
    let sourceURL: URL
    let pdfURL: URL?
}

private final class ArXivHotPaperFeedParser: NSObject, XMLParserDelegate {
    private var entries: [ArXivHotPaperEntry] = []
    private var currentEntry: ParsedEntry?
    private var currentValue = ""
    private var currentAuthorName = ""
    private var isInsideAuthor = false
    private let dateFormatter = ISO8601DateFormatter()

    func parse(data: Data) throws -> [ArXivHotPaperEntry] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? HotPaperDiscoveryError.invalidServerResponse
        }
        return entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentValue = ""
        let normalizedName = normalizedElementName(elementName: elementName, qualifiedName: qName)

        if normalizedName == "entry" {
            currentEntry = ParsedEntry()
            return
        }

        guard currentEntry != nil else { return }

        if normalizedName == "author" {
            isInsideAuthor = true
            currentAuthorName = ""
        }

        if normalizedName == "category",
           currentEntry?.primaryCategory == nil,
           let term = attributeDict["term"],
           term.isEmpty == false {
            currentEntry?.primaryCategory = term
        }

        if normalizedName == "link",
           let href = attributeDict["href"],
           attributeDict["title"]?.lowercased().contains("pdf") == true {
            currentEntry?.pdfURL = URL(string: href)
        }

        if normalizedName == "link",
           currentEntry?.pdfURL == nil,
           let href = attributeDict["href"],
           attributeDict["type"]?.lowercased() == "application/pdf" {
            currentEntry?.pdfURL = URL(string: href)
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
        let normalizedName = normalizedElementName(elementName: elementName, qualifiedName: qName)
        let text = currentValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard var currentEntry else { return }

        if isInsideAuthor, normalizedName == "name", text.isEmpty == false {
            currentAuthorName = text
        }

        switch normalizedName {
        case "id":
            if currentEntry.id == nil, text.isEmpty == false {
                currentEntry.id = text
                currentEntry.sourceURL = URL(string: text)
            }
        case "title":
            if currentEntry.title == nil, text.isEmpty == false {
                currentEntry.title = text
            }
        case "summary":
            if currentEntry.summary == nil, text.isEmpty == false {
                currentEntry.summary = text
            }
        case "published":
            if currentEntry.publishedAt == nil {
                currentEntry.publishedAt = dateFormatter.date(from: text)
            }
        case "updated":
            if currentEntry.updatedAt == nil {
                currentEntry.updatedAt = dateFormatter.date(from: text)
            }
        case "author":
            if currentAuthorName.isEmpty == false {
                currentEntry.authors.append(currentAuthorName)
            }
            isInsideAuthor = false
            currentAuthorName = ""
        case "entry":
            if let entry = currentEntry.makeEntry() {
                entries.append(entry)
            }
            self.currentEntry = nil
            currentValue = ""
            return
        default:
            break
        }

        self.currentEntry = currentEntry
        currentValue = ""
    }

    private func normalizedElementName(elementName: String, qualifiedName: String?) -> String {
        let candidate = qualifiedName ?? elementName
        return candidate.components(separatedBy: ":").last?.lowercased() ?? candidate.lowercased()
    }

    private struct ParsedEntry {
        var id: String?
        var title: String?
        var summary: String?
        var authors: [String] = []
        var primaryCategory: String?
        var publishedAt: Date?
        var updatedAt: Date?
        var sourceURL: URL?
        var pdfURL: URL?

        func makeEntry() -> ArXivHotPaperEntry? {
            guard let id,
                  let title,
                  let summary,
                  let publishedAt,
                  let updatedAt,
                  let sourceURL else {
                return nil
            }

            return ArXivHotPaperEntry(
                id: id,
                title: title,
                summary: summary,
                authors: authors,
                primaryCategory: primaryCategory ?? "",
                publishedAt: publishedAt,
                updatedAt: updatedAt,
                sourceURL: sourceURL,
                pdfURL: pdfURL
            )
        }
    }
}
