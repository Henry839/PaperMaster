import Foundation
import Observation

enum FusionMaterialSelection {
    static let minimumPaperCount = 2
    static let maximumPaperCount = 6
}

enum FusionMaterialAddOutcome: Equatable {
    case added
    case duplicate
    case limitReached
}

struct PaperFusionInput: Sendable {
    let paperID: UUID
    let title: String
    let authorsText: String
    let abstractText: String
    let tagNames: [String]
}

struct PaperFusionIdea: Identifiable, Equatable, Sendable {
    let title: String
    let hypothesis: String
    let rationale: String

    var id: String {
        "\(title)|\(hypothesis)"
    }
}

struct PaperFusionResult: Equatable, Sendable {
    let selectedPaperIDs: [UUID]
    let ideas: [PaperFusionIdea]
    let generatedAt: Date
}

@MainActor
@Observable
final class FusionReactorSession {
    var selectedPaperIDs: [UUID] = []
    var result: PaperFusionResult?
    var isFusing = false

    var canFuse: Bool {
        selectedPaperIDs.count >= FusionMaterialSelection.minimumPaperCount && isFusing == false
    }

    @discardableResult
    func addMaterial(_ paperID: UUID) -> FusionMaterialAddOutcome {
        if selectedPaperIDs.contains(paperID) {
            return .duplicate
        }

        guard selectedPaperIDs.count < FusionMaterialSelection.maximumPaperCount else {
            return .limitReached
        }

        selectedPaperIDs.append(paperID)
        invalidateResult()
        return .added
    }

    func removeMaterial(_ paperID: UUID) {
        let previousCount = selectedPaperIDs.count
        selectedPaperIDs.removeAll { $0 == paperID }
        if selectedPaperIDs.count != previousCount {
            invalidateResult()
        }
    }

    func clearMaterials() {
        guard selectedPaperIDs.isEmpty == false || result != nil else { return }
        selectedPaperIDs = []
        result = nil
    }

    func syncMaterials(allowedPaperIDs: Set<UUID>) {
        let filteredIDs = selectedPaperIDs.filter { allowedPaperIDs.contains($0) }
        guard filteredIDs != selectedPaperIDs else { return }
        selectedPaperIDs = filteredIDs
        result = nil
    }

    func beginFusion() {
        isFusing = true
        result = nil
    }

    func finishFusion(with result: PaperFusionResult?) {
        isFusing = false
        self.result = result
    }

    func reset() {
        selectedPaperIDs = []
        result = nil
        isFusing = false
    }

    private func invalidateResult() {
        result = nil
    }
}
