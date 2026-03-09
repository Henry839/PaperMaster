import Foundation
import XCTest
@testable import PaperReadingScheduler

final class SchedulerServiceTests: XCTestCase {
    func testDistributesPapersByDailyCapacity() {
        let scheduler = SchedulerService(calendar: Self.calendar)
        let referenceDate = Self.referenceDate
        let items = [
            SchedulingItem(id: UUID(), status: .scheduled, queuePosition: 0, dueDate: nil, manualDueDateOverride: nil, dateAdded: referenceDate),
            SchedulingItem(id: UUID(), status: .scheduled, queuePosition: 1, dueDate: nil, manualDueDateOverride: nil, dateAdded: referenceDate.addingTimeInterval(1)),
            SchedulingItem(id: UUID(), status: .scheduled, queuePosition: 2, dueDate: nil, manualDueDateOverride: nil, dateAdded: referenceDate.addingTimeInterval(2))
        ]

        let plan = scheduler.makePlan(for: items, papersPerDay: 2, referenceDate: referenceDate)

        XCTAssertEqual(plan[items[0].id]?.dueDate, Self.day(0))
        XCTAssertEqual(plan[items[1].id]?.dueDate, Self.day(0))
        XCTAssertEqual(plan[items[2].id]?.dueDate, Self.day(1))
    }

    func testManualSnoozeOverrideIsRespected() {
        let scheduler = SchedulerService(calendar: Self.calendar)
        let referenceDate = Self.referenceDate
        let items = [
            SchedulingItem(id: UUID(), status: .scheduled, queuePosition: 0, dueDate: nil, manualDueDateOverride: nil, dateAdded: referenceDate),
            SchedulingItem(id: UUID(), status: .scheduled, queuePosition: 1, dueDate: nil, manualDueDateOverride: Self.day(1), dateAdded: referenceDate.addingTimeInterval(1))
        ]

        let plan = scheduler.makePlan(for: items, papersPerDay: 1, referenceDate: referenceDate)

        XCTAssertEqual(plan[items[0].id]?.dueDate, Self.day(0))
        XCTAssertEqual(plan[items[1].id]?.dueDate, Self.day(1))
    }

    func testOverdueItemsRemainLockedWhileFutureItemsRebalance() {
        let scheduler = SchedulerService(calendar: Self.calendar)
        let referenceDate = Self.referenceDate
        let items = [
            SchedulingItem(id: UUID(), status: .scheduled, queuePosition: 0, dueDate: Self.day(-1), manualDueDateOverride: nil, dateAdded: referenceDate),
            SchedulingItem(id: UUID(), status: .scheduled, queuePosition: 1, dueDate: Self.day(3), manualDueDateOverride: nil, dateAdded: referenceDate.addingTimeInterval(1))
        ]

        let plan = scheduler.makePlan(for: items, papersPerDay: 1, referenceDate: referenceDate)

        XCTAssertEqual(plan[items[0].id]?.dueDate, Self.day(-1))
        XCTAssertEqual(plan[items[1].id]?.dueDate, Self.day(0))
    }

    func testDueTodayScheduledItemsRebalanceWhenQueueOrderChanges() {
        let scheduler = SchedulerService(calendar: Self.calendar)
        let referenceDate = Self.referenceDate
        let items = [
            SchedulingItem(id: UUID(), status: .scheduled, queuePosition: 0, dueDate: Self.day(1), manualDueDateOverride: nil, dateAdded: referenceDate),
            SchedulingItem(id: UUID(), status: .scheduled, queuePosition: 1, dueDate: Self.day(0), manualDueDateOverride: nil, dateAdded: referenceDate.addingTimeInterval(1))
        ]

        let plan = scheduler.makePlan(for: items, papersPerDay: 1, referenceDate: referenceDate)

        XCTAssertEqual(plan[items[0].id]?.dueDate, Self.day(0))
        XCTAssertEqual(plan[items[1].id]?.dueDate, Self.day(1))
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9))!

    private static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: referenceDate))!
    }
}
