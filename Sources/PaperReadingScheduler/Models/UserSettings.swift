import Foundation
import SwiftData

@Model
final class UserSettings {
    @Attribute(.unique) var id: UUID
    var papersPerDay: Int
    var dailyReminderTime: Date
    var autoCachePDFs: Bool
    var defaultImportBehaviorRawValue: String
    var aiTaggingEnabled: Bool
    var aiTaggingBaseURLString: String
    var aiTaggingModel: String

    init(
        id: UUID = UUID(),
        papersPerDay: Int = 1,
        dailyReminderTime: Date = UserSettings.defaultReminderDate(),
        autoCachePDFs: Bool = false,
        defaultImportBehavior: ImportBehavior = .scheduleImmediately,
        aiTaggingEnabled: Bool = false,
        aiTaggingBaseURLString: String = "https://api.openai.com/v1",
        aiTaggingModel: String = "gpt-4o-mini"
    ) {
        self.id = id
        self.papersPerDay = papersPerDay
        self.dailyReminderTime = dailyReminderTime
        self.autoCachePDFs = autoCachePDFs
        self.defaultImportBehaviorRawValue = defaultImportBehavior.rawValue
        self.aiTaggingEnabled = aiTaggingEnabled
        self.aiTaggingBaseURLString = aiTaggingBaseURLString
        self.aiTaggingModel = aiTaggingModel
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

    func aiTaggingReadiness(apiKey: String?) -> AITaggingReadiness {
        guard aiTaggingEnabled else { return .disabled }

        let trimmedBaseURL = aiTaggingBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedBaseURL.isEmpty == false else {
            return .missingBaseURL
        }
        guard let baseURL = URL(string: trimmedBaseURL), baseURL.scheme?.hasPrefix("http") == true else {
            return .invalidBaseURL
        }

        let trimmedModel = aiTaggingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedModel.isEmpty == false else {
            return .missingModel
        }

        let trimmedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmedAPIKey.isEmpty == false else {
            return .missingAPIKey
        }

        return .ready(
            PaperTaggingConfiguration(
                baseURL: baseURL,
                model: trimmedModel,
                apiKey: trimmedAPIKey
            )
        )
    }

    func aiTaggingConfiguration(apiKey: String?) -> PaperTaggingConfiguration? {
        guard case let .ready(configuration) = aiTaggingReadiness(apiKey: apiKey) else {
            return nil
        }
        return configuration
    }
}
