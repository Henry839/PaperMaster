import Foundation
import XCTest
@testable import PaperReadingScheduler

@MainActor
final class ReminderServiceTests: XCTestCase {
    func testSchedulesDailySummaryAndDueNotification() async throws {
        let center = FakeNotificationCenter()
        let service = ReminderService(center: center, calendar: Self.calendar)
        let settings = UserSettings(dailyReminderTime: Self.reminderDate)
        let paper = Paper(title: "Chain of Thought", status: .scheduled, dueDate: Self.referenceDate)

        await service.syncNotifications(for: [paper], settings: settings, now: Self.nowBeforeReminder)

        let identifiers = center.requestIdentifiers
        let summaryIdentifier = ReminderService.dailySummaryIdentifier

        XCTAssertTrue(identifiers.contains(summaryIdentifier))
        XCTAssertTrue(identifiers.contains(where: { $0.hasPrefix("paper-due-") }))
        XCTAssertEqual(center.firstPaperID(withIdentifierPrefix: "paper-due-"), paper.id.uuidString)
    }

    func testDonePaperDoesNotSchedulePerPaperNotification() async throws {
        let center = FakeNotificationCenter()
        let service = ReminderService(center: center, calendar: Self.calendar)
        let settings = UserSettings(dailyReminderTime: Self.reminderDate)
        let paper = Paper(title: "Done Paper", status: .done, dueDate: Self.referenceDate)

        await service.syncNotifications(for: [paper], settings: settings, now: Self.nowBeforeReminder)

        XCTAssertEqual(center.requestIdentifiers, [ReminderService.dailySummaryIdentifier])
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 0))!
    private static let reminderDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9))!
    private static let nowBeforeReminder = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 8))!
}
