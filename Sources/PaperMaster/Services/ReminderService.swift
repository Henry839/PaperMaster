import Foundation
@preconcurrency import UserNotifications

@MainActor
protocol NotificationSchedulingCenter: AnyObject, Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
}

@MainActor
final class UserNotificationCenterAdapter: NotificationSchedulingCenter, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: options) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeAllPendingNotificationRequests() {
        center.removeAllPendingNotificationRequests()
    }
}

@MainActor
struct ReminderService: Sendable {
    static let dailySummaryIdentifier = "daily-summary"

    let center: NotificationSchedulingCenter
    let calendar: Calendar

    init(center: NotificationSchedulingCenter = UserNotificationCenterAdapter(), calendar: Calendar = .current) {
        self.center = center
        self.calendar = calendar
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func syncNotifications(
        for papers: [Paper],
        settings: UserSettings,
        now: Date = .now
    ) async {
        center.removeAllPendingNotificationRequests()

        do {
            try await center.add(makeDailySummaryRequest(settings: settings))

            for paper in papers where paper.status.isActiveQueue {
                if let request = makePaperReminderRequest(for: paper, settings: settings, now: now) {
                    try await center.add(request)
                }
            }
        } catch {
            // Notification failures should not block app usage.
        }
    }

    func cancelNotifications(for paperIDs: [UUID]) {
        let ids = paperIDs.flatMap { id in
            [
                identifier(for: id, prefix: "paper-due"),
                identifier(for: id, prefix: "paper-overdue")
            ]
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func makeDailySummaryRequest(settings: UserSettings) -> UNNotificationRequest {
        let reminderComponents = calendar.dateComponents([.hour, .minute], from: settings.dailyReminderTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: reminderComponents, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "Paper reading queue"
        content.body = "Review today’s due and overdue papers."
        content.sound = .default
        content.userInfo = ["destination": "today"]
        return UNNotificationRequest(identifier: Self.dailySummaryIdentifier, content: content, trigger: trigger)
    }

    func makePaperReminderRequest(
        for paper: Paper,
        settings: UserSettings,
        now: Date = .now
    ) -> UNNotificationRequest? {
        guard let dueDate = paper.dueDate else { return nil }
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: dueDate)
        let reminderTime = calendar.dateComponents([.hour, .minute], from: settings.dailyReminderTime)
        let reminderDate = calendar.date(
            bySettingHour: reminderTime.hour ?? 9,
            minute: reminderTime.minute ?? 0,
            second: 0,
            of: dueDay
        ) ?? dueDay

        let isOverdue = dueDay < today || reminderDate < now
        let fireDate = isOverdue ? now.addingTimeInterval(60) : reminderDate
        let interval = max(1, fireDate.timeIntervalSince(now))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let content = UNMutableNotificationContent()
        content.title = isOverdue ? "Overdue paper" : "Paper due today"
        content.body = paper.title
        content.sound = .default
        content.userInfo = [
            "destination": "paper",
            "paperID": paper.id.uuidString
        ]

        let prefix = isOverdue ? "paper-overdue" : "paper-due"
        return UNNotificationRequest(
            identifier: identifier(for: paper.id, prefix: prefix),
            content: content,
            trigger: trigger
        )
    }

    private func identifier(for id: UUID, prefix: String) -> String {
        "\(prefix)-\(id.uuidString)"
    }
}
