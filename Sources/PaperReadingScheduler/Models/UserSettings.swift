import Foundation
import SwiftData

@Model
final class UserSettings {
    @Attribute(.unique) var id: UUID
    var papersPerDay: Int
    var dailyReminderTime: Date
    var autoCachePDFs: Bool
    var defaultImportBehaviorRawValue: String

    init(
        id: UUID = UUID(),
        papersPerDay: Int = 1,
        dailyReminderTime: Date = UserSettings.defaultReminderDate(),
        autoCachePDFs: Bool = false,
        defaultImportBehavior: ImportBehavior = .scheduleImmediately
    ) {
        self.id = id
        self.papersPerDay = papersPerDay
        self.dailyReminderTime = dailyReminderTime
        self.autoCachePDFs = autoCachePDFs
        self.defaultImportBehaviorRawValue = defaultImportBehavior.rawValue
    }

    var defaultImportBehavior: ImportBehavior {
        get { ImportBehavior(rawValue: defaultImportBehaviorRawValue) ?? .scheduleImmediately }
        set { defaultImportBehaviorRawValue = newValue.rawValue }
    }

    static func defaultReminderDate(calendar: Calendar = .current) -> Date {
        let now = Date()
        return calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: now
        ) ?? now
    }
}
