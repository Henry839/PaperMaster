import Foundation

enum HotPaperCategory: String, CaseIterable, Identifiable, Sendable {
    case machineLearning
    case languageModels
    case computerVision
    case artificialIntelligence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .machineLearning:
            "Machine Learning"
        case .languageModels:
            "Language Models"
        case .computerVision:
            "Computer Vision"
        case .artificialIntelligence:
            "AI"
        }
    }

    var arxivQueryValue: String {
        switch self {
        case .machineLearning:
            "cs.LG"
        case .languageModels:
            "cs.CL"
        case .computerVision:
            "cs.CV"
        case .artificialIntelligence:
            "cs.AI"
        }
    }

    var description: String {
        switch self {
        case .machineLearning:
            "Fresh submissions from the core machine learning feed."
        case .languageModels:
            "Recent language model and NLP papers."
        case .computerVision:
            "New vision papers from the arXiv stream."
        case .artificialIntelligence:
            "General AI papers across planning, agents, and reasoning."
        }
    }
}

struct HotPaper: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let authors: [String]
    let summary: String
    let primaryCategory: String
    let publishedAt: Date
    let updatedAt: Date
    let sourceURL: URL
    let pdfURL: URL?
    let score: Double
    let scoreLabel: String
    let reasons: [String]

    var authorsText: String {
        authors.isEmpty ? "Unknown authors" : authors.joined(separator: ", ")
    }
}
