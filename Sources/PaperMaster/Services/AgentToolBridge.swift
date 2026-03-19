import Foundation

struct AgentPaperSearchResult: Identifiable, Equatable {
    let id: UUID
    let title: String
    let authorsText: String
    let status: String
    let tagNames: [String]
}

struct AgentPaperDetailSnapshot: Equatable {
    let id: UUID
    let title: String
    let authorsText: String
    let abstractText: String
    let notes: String
    let status: String
    let dueDate: Date?
    let tagNames: [String]
    let sourceURL: URL?
    let pdfURL: URL?
}

struct AgentQueuePlanItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let queuePosition: Int
    let dueDate: Date?
}

enum AgentToolBridge {
    static func searchPapers(query: String, in papers: [Paper]) -> [AgentPaperSearchResult] {
        papers
            .filter { $0.matchesSearch(query) }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return lhs.status.rawValue < rhs.status.rawValue
                }
                return lhs.dateAdded > rhs.dateAdded
            }
            .map {
                AgentPaperSearchResult(
                    id: $0.id,
                    title: $0.title,
                    authorsText: $0.authorsDisplayText,
                    status: $0.status.rawValue,
                    tagNames: $0.tagNames
                )
            }
    }

    static func listToday(papers: [Paper], calendar: Calendar = .current, referenceDate: Date = .now) -> [AgentQueuePlanItem] {
        papers
            .filter { $0.isDueTodayOrOverdue(calendar: calendar, referenceDate: referenceDate) }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate != rhsDate {
                        return lhsDate < rhsDate
                    }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
                return lhs.queuePosition < rhs.queuePosition
            }
            .map {
                AgentQueuePlanItem(
                    id: $0.id,
                    title: $0.title,
                    queuePosition: $0.queuePosition,
                    dueDate: $0.dueDate
                )
            }
    }

    static func detail(for paper: Paper) -> AgentPaperDetailSnapshot {
        AgentPaperDetailSnapshot(
            id: paper.id,
            title: paper.title,
            authorsText: paper.authorsDisplayText,
            abstractText: paper.abstractText,
            notes: paper.notes,
            status: paper.status.rawValue,
            dueDate: paper.dueDate,
            tagNames: paper.tagNames,
            sourceURL: paper.sourceURL,
            pdfURL: paper.pdfURL ?? paper.cachedPDFURL ?? paper.managedPDFLocalURL
        )
    }

    static func proposedQueuePlan(
        papers: [Paper],
        papersPerDay: Int,
        schedulerService: SchedulerService,
        referenceDate: Date = .now
    ) -> [AgentQueuePlanItem] {
        let plan = schedulerService.makePlan(
            for: papers.map(SchedulingItem.init),
            papersPerDay: papersPerDay,
            referenceDate: referenceDate
        )
        return papers
            .filter { $0.status.isActiveQueue }
            .compactMap { paper in
                guard let placement = plan[paper.id] else { return nil }
                return AgentQueuePlanItem(
                    id: paper.id,
                    title: paper.title,
                    queuePosition: placement.queuePosition,
                    dueDate: placement.dueDate
                )
            }
            .sorted { lhs, rhs in
                if lhs.queuePosition != rhs.queuePosition {
                    return lhs.queuePosition < rhs.queuePosition
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }
}
