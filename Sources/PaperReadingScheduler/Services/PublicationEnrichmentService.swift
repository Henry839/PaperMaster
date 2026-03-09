import Foundation

struct PublicationEnrichmentRequest: Sendable {
    var title: String
    var authors: [String]
    var sourceURL: URL?
    var pdfURL: URL?
    var arxivID: String?
    var doi: String?
    var publishedYear: Int?
}

struct PublicationEnrichmentResult: Sendable, Equatable {
    var venueKey: String?
    var venueName: String?
    var doi: String?
    var bibtex: String?
}

protocol PublicationEnriching: Sendable {
    func enrich(for request: PublicationEnrichmentRequest) async -> PublicationEnrichmentResult
}

struct CrossrefPublicationEnricher: PublicationEnriching {
    let networking: HTTPNetworking
    let decoder: JSONDecoder

    init(
        networking: HTTPNetworking = URLSessionHTTPNetworking(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.networking = networking
        self.decoder = decoder
    }

    func enrich(for request: PublicationEnrichmentRequest) async -> PublicationEnrichmentResult {
        let normalizedDOI = normalizeDOI(request.doi)
        let arxivID = request.arxivID
            ?? request.sourceURL?.canonicalArxivIdentifier
            ?? request.pdfURL?.canonicalArxivIdentifier

        do {
            if let publishedMatch = try await resolvePublishedMatch(for: request, doi: normalizedDOI) {
                let venueMatch = VenueCatalog.match(for: publishedMatch.work.venueCandidates)
                let fallbackVenueName = publishedMatch.work.preferredVenueName
                guard venueMatch != nil || fallbackVenueName?.isEmpty == false else {
                    throw URLError(.resourceUnavailable)
                }
                return PublicationEnrichmentResult(
                    venueKey: venueMatch?.key,
                    venueName: venueMatch?.name ?? fallbackVenueName,
                    doi: publishedMatch.work.doi ?? normalizedDOI,
                    bibtex: makePublishedBibTeX(
                        work: publishedMatch.work,
                        request: request,
                        venueMatch: venueMatch,
                        fallbackVenueName: fallbackVenueName
                    )
                )
            }
        } catch {
            // Keep import non-blocking when venue lookup fails.
        }

        guard let arxivID else {
            return PublicationEnrichmentResult(doi: normalizedDOI)
        }

        let bibtex = await fetchArxivBibTeX(arxivID: arxivID, sourceURL: request.sourceURL)
        return PublicationEnrichmentResult(
            venueKey: nil,
            venueName: nil,
            doi: normalizedDOI,
            bibtex: bibtex
        )
    }

    private func resolvePublishedMatch(
        for request: PublicationEnrichmentRequest,
        doi: String?
    ) async throws -> PublishedMatch? {
        if let doi, let work = try await fetchCrossrefWork(doi: doi) {
            let titleScore = titleSimilarityScore(request.title, work.preferredTitle)
            if titleScore >= 0.74, authorsAreCompatible(request.authors, candidate: work.authors), yearsAreCompatible(request.publishedYear, candidate: work.year) {
                return PublishedMatch(work: work)
            }
        }

        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false else { return nil }

        let searchResults = try await searchCrossrefWorks(
            title: title,
            authors: request.authors
        )

        let publishedMatches = searchResults
            .compactMap { work -> PublishedMatch? in
                let titleScore = titleSimilarityScore(title, work.preferredTitle)
                guard titleScore >= 0.92 else { return nil }
                guard authorsAreCompatible(request.authors, candidate: work.authors) else { return nil }
                guard yearsAreCompatible(request.publishedYear, candidate: work.year) else { return nil }
                return PublishedMatch(work: work, titleScore: titleScore)
            }
            .sorted(by: { lhs, rhs in
                if lhs.titleScore != rhs.titleScore {
                    return lhs.titleScore > rhs.titleScore
                }
                return (lhs.work.year ?? 0) > (rhs.work.year ?? 0)
            })

        return publishedMatches.first
    }

    private func fetchCrossrefWork(doi: String) async throws -> CrossrefWork? {
        var request = URLRequest(url: crossrefWorkURL(for: doi))
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await networking.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return nil }

        if httpResponse.statusCode == 404 {
            return nil
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try decoder.decode(CrossrefSingleWorkResponse.self, from: data).message
    }

    private func searchCrossrefWorks(title: String, authors: [String]) async throws -> [CrossrefWork] {
        guard let url = crossrefSearchURL(title: title, authors: authors) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await networking.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try decoder.decode(CrossrefSearchResponse.self, from: data).message.items
    }

    private func crossrefWorkURL(for doi: String) -> URL {
        URL(string: "https://api.crossref.org/works")!
            .appendingPathComponent(doi)
    }

    private func crossrefSearchURL(title: String, authors: [String]) -> URL? {
        var components = URLComponents(string: "https://api.crossref.org/works")
        let firstAuthor = authors.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        components?.queryItems = [
            URLQueryItem(name: "query.title", value: title),
            URLQueryItem(name: "query.author", value: firstAuthor.isEmpty ? nil : firstAuthor),
            URLQueryItem(name: "rows", value: "5")
        ]

        return components?.url
    }

    private func authorsAreCompatible(_ requestAuthors: [String], candidate: [CrossrefAuthor]) -> Bool {
        let requestFamilies = Set(
            requestAuthors
                .compactMap(extractFamilyName(from:))
                .map(normalizeAuthorComponent)
                .filter { $0.isEmpty == false }
        )
        let candidateFamilies = Set(
            candidate
                .compactMap(\.family)
                .map(normalizeAuthorComponent)
                .filter { $0.isEmpty == false }
        )

        if requestFamilies.isEmpty || candidateFamilies.isEmpty {
            return true
        }

        return requestFamilies.isDisjoint(with: candidateFamilies) == false
    }

    private func yearsAreCompatible(_ requestYear: Int?, candidate: Int?) -> Bool {
        guard let requestYear, let candidate else { return true }
        return abs(requestYear - candidate) <= 2
    }

    private func fetchArxivBibTeX(arxivID: String, sourceURL: URL?) async -> String? {
        do {
            let abstractURL = sourceURL?.arxivAbstractURL ?? URL(string: "https://arxiv.org/abs/\(arxivID)")
            guard let abstractURL else { return nil }

            let abstractHTML = try await fetchText(from: abstractURL)
            let fallbackBibTeXURL = URL(string: "https://arxiv.org/bibtex/\(arxivID)")

            let bibTeXURL = extractBibTeXLink(from: abstractHTML, relativeTo: abstractURL)
                ?? fallbackBibTeXURL

            if let bibTeXURL {
                let bibTeXPayload = try await fetchText(from: bibTeXURL)
                if let extracted = extractBibTeXBlock(from: bibTeXPayload) {
                    return extracted
                }
            }

            return extractBibTeXBlock(from: abstractHTML)
        } catch {
            return nil
        }
    }

    private func fetchText(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("text/html, text/plain;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await networking.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return String(decoding: data, as: UTF8.self)
    }

    private func extractBibTeXLink(from html: String, relativeTo baseURL: URL) -> URL? {
        let pattern = #"<a[^>]+href=["']([^"']+)["'][^>]*>\s*Export BibTeX Citation\s*</a>"#

        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = expression.firstMatch(in: html, options: [], range: nsRange),
              let hrefRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return URL(string: String(html[hrefRange]), relativeTo: baseURL)?.absoluteURL
    }

    private func extractBibTeXBlock(from rawText: String) -> String? {
        guard let atIndex = rawText.firstIndex(of: "@"),
              let openingBraceIndex = rawText[atIndex...].firstIndex(of: "{") else {
            return nil
        }

        var depth = 0
        var index = openingBraceIndex

        while index < rawText.endIndex {
            let character = rawText[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    let bibTeX = rawText[atIndex...index]
                    return bibTeX
                        .replacingOccurrences(of: "\r\n", with: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            index = rawText.index(after: index)
        }

        return nil
    }

    private func makePublishedBibTeX(
        work: CrossrefWork,
        request: PublicationEnrichmentRequest,
        venueMatch: VenueCatalogEntry?,
        fallbackVenueName: String?
    ) -> String? {
        let title = work.preferredTitle.isEmpty ? request.title.trimmingCharacters(in: .whitespacesAndNewlines) : work.preferredTitle
        guard title.isEmpty == false else { return nil }

        let authors = work.preferredAuthors.isEmpty ? request.authors : work.preferredAuthors
        let year = work.year ?? request.publishedYear
        let venueFieldKind = venueMatch?.fieldKind ?? work.preferredVenueFieldKind
        let venueFieldName = venueFieldKind.rawValue
        let venueFieldValue: String?

        if let venueMatch {
            venueFieldValue = venueMatch.key
        } else if let fallbackVenueName, fallbackVenueName.isEmpty == false {
            venueFieldValue = "{\(escapeBibTeXValue(fallbackVenueName))}"
        } else {
            venueFieldValue = nil
        }

        let entryType = work.preferredEntryType.rawValue
        let citationKey = makeCitationKey(
            authors: authors,
            year: year,
            title: title
        )

        var lines = ["@\(entryType){\(citationKey),"]
        lines.append("  title = {\(escapeBibTeXValue(title))},")

        if authors.isEmpty == false {
            lines.append("  author = {\(escapeBibTeXValue(authors.joined(separator: " and ")))},")
        }

        if let year {
            lines.append("  year = {\(year)},")
        }

        if let venueFieldValue {
            lines.append("  \(venueFieldName) = \(venueFieldValue),")
        }

        if let volume = work.volume?.trimmingCharacters(in: .whitespacesAndNewlines), volume.isEmpty == false {
            lines.append("  volume = {\(escapeBibTeXValue(volume))},")
        }

        if let issue = work.issue?.trimmingCharacters(in: .whitespacesAndNewlines), issue.isEmpty == false {
            lines.append("  number = {\(escapeBibTeXValue(issue))},")
        }

        if let page = work.page?.trimmingCharacters(in: .whitespacesAndNewlines), page.isEmpty == false {
            lines.append("  pages = {\(escapeBibTeXValue(page))},")
        }

        if let doi = work.doi {
            lines.append("  doi = {\(escapeBibTeXValue(doi))},")
            lines.append("  url = {https://doi.org/\(escapeBibTeXValue(doi))},")
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func makeCitationKey(authors: [String], year: Int?, title: String) -> String {
        let authorComponent = authors
            .compactMap(extractFamilyName(from:))
            .map(normalizeCitationKeyComponent)
            .first { $0.isEmpty == false } ?? "paper"
        let yearComponent = year.map(String.init) ?? "nd"
        let titleComponent = significantTitleWord(from: title)
        return authorComponent + yearComponent + titleComponent
    }

    private func significantTitleWord(from title: String) -> String {
        let stopWords: Set<String> = [
            "a", "an", "the", "and", "for", "from", "in", "of", "on", "to", "toward", "towards", "with"
        ]
        let normalizedWords = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }

        let selected = normalizedWords.first(where: { stopWords.contains($0) == false }) ?? normalizedWords.first ?? "paper"
        return normalizeCitationKeyComponent(selected)
    }

    private func titleSimilarityScore(_ lhs: String, _ rhs: String) -> Double {
        let normalizedLeft = normalizeTitle(lhs)
        let normalizedRight = normalizeTitle(rhs)

        guard normalizedLeft.isEmpty == false, normalizedRight.isEmpty == false else {
            return 0
        }

        if normalizedLeft == normalizedRight {
            return 1
        }

        if normalizedLeft.contains(normalizedRight) || normalizedRight.contains(normalizedLeft) {
            let shorterLength = Double(min(normalizedLeft.count, normalizedRight.count))
            let longerLength = Double(max(normalizedLeft.count, normalizedRight.count))
            return shorterLength / longerLength
        }

        let leftTokens = Set(normalizedLeft.split(separator: " ").map(String.init))
        let rightTokens = Set(normalizedRight.split(separator: " ").map(String.init))
        let intersection = leftTokens.intersection(rightTokens)
        let union = leftTokens.union(rightTokens)

        guard union.isEmpty == false else { return 0 }
        return Double(intersection.count) / Double(union.count)
    }

    private func normalizeTitle(_ title: String) -> String {
        title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeDOI(_ doi: String?) -> String? {
        guard var doi = doi?.trimmingCharacters(in: .whitespacesAndNewlines), doi.isEmpty == false else {
            return nil
        }

        doi = doi.replacingOccurrences(
            of: #"^https?://(dx\.)?doi\.org/"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        return doi.isEmpty ? nil : doi
    }

    private func extractFamilyName(from author: String) -> String? {
        let components = author
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.isEmpty == false }

        return components.last
    }

    private func normalizeAuthorComponent(_ author: String) -> String {
        author
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }

    private func normalizeCitationKeyComponent(_ value: String) -> String {
        normalizeAuthorComponent(value)
    }

    private func escapeBibTeXValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
    }
}

private struct PublishedMatch {
    let work: CrossrefWork
    let titleScore: Double

    init(work: CrossrefWork, titleScore: Double = 1) {
        self.work = work
        self.titleScore = titleScore
    }
}

private enum BibTeXEntryType: String {
    case article
    case inproceedings
}

private enum VenueFieldKind: String {
    case journal
    case booktitle
}

private struct VenueCatalogEntry {
    let key: String
    let name: String
    let fieldKind: VenueFieldKind
    let aliases: [String]

    func matches(_ candidate: String) -> Bool {
        let normalizedCandidate = VenueCatalog.normalize(candidate)
        return aliases.contains { alias in
            normalizedCandidate == alias || normalizedCandidate.contains(alias)
        }
    }
}

private enum VenueCatalog {
    static func match(for candidates: [String]) -> VenueCatalogEntry? {
        let trimmedCandidates = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        guard trimmedCandidates.isEmpty == false else { return nil }

        return entries
            .compactMap { entry -> (VenueCatalogEntry, Int)? in
                let bestAliasLength = trimmedCandidates.reduce(into: 0) { bestLength, candidate in
                    for alias in entry.aliases where entry.matches(candidate) {
                        bestLength = max(bestLength, alias.count)
                    }
                }
                return bestAliasLength > 0 ? (entry, bestAliasLength) : nil
            }
            .sorted(by: { lhs, rhs in lhs.1 > rhs.1 })
            .first?
            .0
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"\b(19|20)\d{2}\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeEntry(
        key: String,
        name: String,
        fieldKind: VenueFieldKind,
        aliases: [String] = []
    ) -> VenueCatalogEntry {
        let sourceAliases = [key, name] + aliases
        let aliasSet = Set(sourceAliases.map(normalize).filter { $0.isEmpty == false })
        let normalizedAliases = Array(aliasSet).sorted(by: { $0.count > $1.count })

        return VenueCatalogEntry(
            key: key,
            name: name,
            fieldKind: fieldKind,
            aliases: normalizedAliases
        )
    }

    static let entries: [VenueCatalogEntry] = [
        makeEntry(key: "PNAS", name: "Proceedings of the National Academy of Sciences (PNAS)", fieldKind: .journal),
        makeEntry(key: "PAMI", name: "Transactions on Pattern Analysis and Machine Intelligence (TPAMI)", fieldKind: .journal, aliases: ["tpami", "ieee transactions on pattern analysis and machine intelligence"]),
        makeEntry(key: "IJCV", name: "International Journal of Computer Vision (IJCV)", fieldKind: .journal),
        makeEntry(key: "CVIU", name: "Computer Vision and Image Understanding (CVIU)", fieldKind: .journal),
        makeEntry(key: "TIP", name: "Transactions on Image Processing (TIP)", fieldKind: .journal, aliases: ["ieee transactions on image processing"]),
        makeEntry(key: "CVPR", name: "Conference on Computer Vision and Pattern Recognition (CVPR)", fieldKind: .booktitle, aliases: ["ieee cvf conference on computer vision and pattern recognition", "computer vision and pattern recognition"]),
        makeEntry(key: "ICCV", name: "International Conference on Computer Vision (ICCV)", fieldKind: .booktitle, aliases: ["ieee cvf international conference on computer vision"]),
        makeEntry(key: "ECCV", name: "European Conference on Computer Vision (ECCV)", fieldKind: .booktitle),
        makeEntry(key: "ACCV", name: "Asian Conference on Computer Vision (ACCV)", fieldKind: .booktitle),
        makeEntry(key: "BMVC", name: "British Machine Vision Conference (BMVC)", fieldKind: .booktitle),
        makeEntry(key: "WACV", name: "Proceedings of Winter Conference on Applications of Computer Vision (WACV)", fieldKind: .booktitle, aliases: ["winter conference on applications of computer vision"]),
        makeEntry(key: "JMLR", name: "Journal of Machine Learning Research (JMLR)", fieldKind: .journal),
        makeEntry(key: "NIPS", name: "Advances in Neural Information Processing Systems (NeurIPS)", fieldKind: .booktitle, aliases: ["neurips", "neural information processing systems", "advances in neural information processing systems"]),
        makeEntry(key: "ICML", name: "International Conference on Machine Learning (ICML)", fieldKind: .booktitle),
        makeEntry(key: "ICLR", name: "International Conference on Learning Representations (ICLR)", fieldKind: .booktitle),
        makeEntry(key: "JAIR", name: "Journal of Artificial Intelligence Research (JAIR)", fieldKind: .journal),
        makeEntry(key: "AIJ", name: "Artificial Intelligence (AI)", fieldKind: .journal),
        makeEntry(key: "AAAI", name: "AAAI Conference on Artificial Intelligence (AAAI)", fieldKind: .booktitle),
        makeEntry(key: "IJCAI", name: "International Joint Conference on Artificial Intelligence (IJCAI)", fieldKind: .booktitle),
        makeEntry(key: "AISTATS", name: "International Conference on Artificial Intelligence and Statistics (AISTATS)", fieldKind: .booktitle),
        makeEntry(key: "ICUAS", name: "International Conference on Unmanned Aircraft Systems (ICUAS)", fieldKind: .booktitle),
        makeEntry(key: "RA-L", name: "IEEE Robotics and Automation Letters (RA-L)", fieldKind: .journal, aliases: ["ral", "robotics and automation letters"]),
        makeEntry(key: "RA-M", name: "IEEE Robotics and Automation Magazine (RA-M)", fieldKind: .journal, aliases: ["ram", "robotics and automation magazine"]),
        makeEntry(key: "TMECH", name: "IEEE/ASME Transactions on Mechatronics (TMECH)", fieldKind: .journal),
        makeEntry(key: "IJRR", name: "International Journal of Robotics Research (IJRR)", fieldKind: .journal),
        makeEntry(key: "TRO", name: "Transactions on Robotics (T-RO)", fieldKind: .journal, aliases: ["t ro", "transactions on robotics"]),
        makeEntry(key: "IROS", name: "International Conference on Intelligent Robots and Systems (IROS)", fieldKind: .booktitle, aliases: ["ieee rsj international conference on intelligent robots and systems"]),
        makeEntry(key: "ICRA", name: "International Conference on Robotics and Automation (ICRA)", fieldKind: .booktitle, aliases: ["ieee international conference on robotics and automation"]),
        makeEntry(key: "RSS", name: "Robotics: Science and Systems (RSS)", fieldKind: .booktitle),
        makeEntry(key: "CoRL", name: "Conference on Robot Learning (CoRL)", fieldKind: .booktitle),
        makeEntry(key: "ROMAN", name: "International Symposium on Robot and Human Interactive Communication (RO-MAN)", fieldKind: .booktitle, aliases: ["ro man", "robot and human interactive communication"]),
        makeEntry(key: "HRI", name: "ACM/IEEE International Conference on Human-Robot Interaction (HRI)", fieldKind: .booktitle, aliases: ["human robot interaction"]),
        makeEntry(key: "TACL", name: "Transactions of the Association for Computational Linguistics (TACL)", fieldKind: .journal),
        makeEntry(key: "ACL", name: "Annual Meeting of the Association for Computational Linguistics (ACL)", fieldKind: .booktitle),
        makeEntry(key: "EMNLP", name: "Annual Conference on Empirical Methods in Natural Language Processing (EMNLP)", fieldKind: .booktitle),
        makeEntry(key: "NAACL", name: "North American Chapter of the Association for Computational Linguistics: Human Language Technologies (NAACL-HLT)", fieldKind: .booktitle, aliases: ["naacl hlt", "north american chapter of the association for computational linguistics human language technologies"]),
        makeEntry(key: "COLING", name: "International Conference on Computational Linguistics (COLING)", fieldKind: .booktitle),
        makeEntry(key: "CoNLL", name: "Conference on Computational Natural Language Learning (CoNLL)", fieldKind: .booktitle),
        makeEntry(key: "SIGDial", name: "Annual Meeting of the Special Interest Group on Discourse and Dialogue (SIGDial)", fieldKind: .booktitle),
        makeEntry(key: "CogSci", name: "Annual Meeting of the Cognitive Science Society (CogSci)", fieldKind: .booktitle),
        makeEntry(key: "TOG", name: "ACM Transactions on Graphics (TOG)", fieldKind: .journal),
        makeEntry(key: "TVCG", name: "IEEE Transactions on Visualization and Computer Graph (TVCG)", fieldKind: .journal, aliases: ["ieee transactions on visualization and computer graphics"]),
        makeEntry(key: "SCA", name: "ACM SIGGRAPH / Eurographics Symposium on Computer Animation (SCA)", fieldKind: .booktitle, aliases: ["symposium on computer animation"]),
        makeEntry(key: "ThreeDV", name: "International Conference on 3D Vision (3DV)", fieldKind: .booktitle, aliases: ["3dv", "international conference on 3d vision"]),
        makeEntry(key: "CGF", name: "Computer Graphics Forum (CGF)", fieldKind: .journal),
        makeEntry(key: "CHI", name: "ACM Conference on Human Factors in Computing Systems (CHI)", fieldKind: .booktitle),
        makeEntry(key: "UbiComp", name: "ACM on Interactive, Mobile, Wearable and Ubiquitous Technologies (UbiComp)", fieldKind: .journal, aliases: ["ubicomp", "proceedings of the acm on interactive mobile wearable and ubiquitous technologies"]),
        makeEntry(key: "UIST", name: "ACM Symposium on User Interface Software and Technology (UIST)", fieldKind: .booktitle),
        makeEntry(key: "AAMAS", name: "International Conference on Autonomous Agents and Multiagent Systems (AAMAS)", fieldKind: .booktitle),
        makeEntry(key: "KDD", name: "ACM SIGKDD International Conference on Knowledge Discovery and Data Mining (KDD)", fieldKind: .booktitle),
        makeEntry(key: "CoRR", name: "Computing Research Repository (CoRR)", fieldKind: .journal, aliases: ["computing research repository", "corr"])
    ]
}

private struct CrossrefSingleWorkResponse: Decodable {
    let message: CrossrefWork
}

private struct CrossrefSearchResponse: Decodable {
    struct Message: Decodable {
        let items: [CrossrefWork]
    }

    let message: Message
}

private struct CrossrefWork: Decodable {
    let doi: String?
    let title: [String]
    let containerTitle: [String]
    let shortContainerTitle: [String]
    let authors: [CrossrefAuthor]
    let type: String?
    let issued: CrossrefDateParts?
    let publishedPrint: CrossrefDateParts?
    let publishedOnline: CrossrefDateParts?
    let page: String?
    let volume: String?
    let issue: String?
    let event: CrossrefEvent?

    enum CodingKeys: String, CodingKey {
        case doi = "DOI"
        case title
        case containerTitle = "container-title"
        case shortContainerTitle = "short-container-title"
        case authors = "author"
        case type
        case issued
        case publishedPrint = "published-print"
        case publishedOnline = "published-online"
        case page
        case volume
        case issue
        case event
    }

    var preferredTitle: String {
        title.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var preferredAuthors: [String] {
        authors.compactMap { author in
            let parts = [author.given, author.family]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }
    }

    var year: Int? {
        issued?.year ?? publishedPrint?.year ?? publishedOnline?.year
    }

    var venueCandidates: [String] {
        [
            event?.name,
            shortContainerTitle.first,
            containerTitle.first
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.isEmpty == false }
    }

    var preferredVenueName: String? {
        venueCandidates.first
    }

    var preferredEntryType: BibTeXEntryType {
        switch preferredVenueFieldKind {
        case .journal:
            return .article
        case .booktitle:
            return .inproceedings
        }
    }

    var preferredVenueFieldKind: VenueFieldKind {
        switch type?.lowercased() {
        case "proceedings-article", "posted-content":
            return .booktitle
        case "journal-article":
            return .journal
        default:
            if event?.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return .booktitle
            }
            return .journal
        }
    }
}

private struct CrossrefAuthor: Decodable {
    let given: String?
    let family: String?
}

private struct CrossrefDateParts: Decodable {
    let dateParts: [[Int]]

    enum CodingKeys: String, CodingKey {
        case dateParts = "date-parts"
    }

    var year: Int? {
        dateParts.first?.first
    }
}

private struct CrossrefEvent: Decodable {
    let name: String?
}
