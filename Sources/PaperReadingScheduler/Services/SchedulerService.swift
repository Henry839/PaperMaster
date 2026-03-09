import Foundation

struct SchedulingItem: Identifiable, Sendable {
    let id: UUID
    var status: PaperStatus
    var queuePosition: Int
    var dueDate: Date?
    var manualDueDateOverride: Date?
    var dateAdded: Date

    init(id: UUID, status: PaperStatus, queuePosition: Int, dueDate: Date?, manualDueDateOverride: Date?, dateAdded: Date) {
        self.id = id
        self.status = status
        self.queuePosition = queuePosition
        self.dueDate = dueDate
        self.manualDueDateOverride = manualDueDateOverride
        self.dateAdded = dateAdded
    }

    init(paper: Paper) {
        self.init(
            id: paper.id,
            status: paper.status,
            queuePosition: paper.queuePosition,
            dueDate: paper.dueDate,
            manualDueDateOverride: paper.manualDueDateOverride,
            dateAdded: paper.dateAdded
        )
    }
}

struct ScheduledPlacement: Sendable {
    var queuePosition: Int
    var dueDate: Date?
}

struct SchedulerService: Sendable {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func makePlan(
        for items: [SchedulingItem],
        papersPerDay: Int,
        referenceDate: Date = .now
    ) -> [UUID: ScheduledPlacement] {
        let capacity = max(1, papersPerDay)
        let today = calendar.startOfDay(for: referenceDate)
        let activeItems = items
            .filter { $0.status.isActiveQueue }
            .sorted { lhs, rhs in
                if lhs.queuePosition != rhs.queuePosition {
                    return lhs.queuePosition < rhs.queuePosition
                }
                return lhs.dateAdded < rhs.dateAdded
            }

        var placements: [UUID: ScheduledPlacement] = [:]
        var occupiedDays: [Date: Int] = [:]
        var lockedIDs = Set<UUID>()

        for (index, item) in activeItems.enumerated() {
            let normalizedDueDate = item.dueDate.map { calendar.startOfDay(for: $0) }
            let shouldLock = item.status == .reading || (normalizedDueDate != nil && normalizedDueDate! < today)
            guard shouldLock else { continue }

            let lockedDate = normalizedDueDate ?? today
            placements[item.id] = ScheduledPlacement(queuePosition: index, dueDate: lockedDate)
            occupiedDays[lockedDate, default: 0] += 1
            lockedIDs.insert(item.id)
        }

        var nextDate = today
        for (index, item) in activeItems.enumerated() where !lockedIDs.contains(item.id) {
            let minimumDate = max(
                nextDate,
                item.manualDueDateOverride.map { calendar.startOfDay(for: $0) } ?? today
            )
            nextDate = minimumDate

            while occupiedDays[nextDate, default: 0] >= capacity {
                guard let incremented = calendar.date(byAdding: .day, value: 1, to: nextDate) else {
                    break
                }
                nextDate = incremented
            }

            placements[item.id] = ScheduledPlacement(queuePosition: index, dueDate: nextDate)
            occupiedDays[nextDate, default: 0] += 1
        }

        return placements
    }

    func applySchedule(
        to papers: [Paper],
        papersPerDay: Int,
        referenceDate: Date = .now
    ) {
        let plan = makePlan(
            for: papers.map(SchedulingItem.init),
            papersPerDay: papersPerDay,
            referenceDate: referenceDate
        )

        for paper in papers {
            if let placement = plan[paper.id] {
                paper.queuePosition = placement.queuePosition
                paper.dueDate = placement.dueDate
            } else if !paper.status.isActiveQueue {
                paper.dueDate = nil
            }
        }
    }
}
