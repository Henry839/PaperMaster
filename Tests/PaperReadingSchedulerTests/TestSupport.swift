import Foundation
import SwiftData
import UserNotifications
@testable import PaperReadingScheduler

struct StubNetworking: Networking {
    let handler: @Sendable (URL) throws -> (Data, URLResponse)

    func data(from url: URL) async throws -> (Data, URLResponse) {
        try handler(url)
    }
}

struct StubMetadataResolver: MetadataResolving {
    var metadata: ResolvedPaperMetadata

    func resolve(url: URL) async throws -> ResolvedPaperMetadata {
        metadata
    }
}

@MainActor
final class FakeNotificationCenter: NotificationSchedulingCenter, @unchecked Sendable {
    private(set) var requests: [UNNotificationRequest] = []

    var requestIdentifiers: [String] {
        requests.map(\.identifier)
    }

    func firstPaperID(withIdentifierPrefix prefix: String) -> String? {
        requests
            .first(where: { $0.identifier.hasPrefix(prefix) })?
            .content.userInfo["paperID"] as? String
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        requests.removeAll { identifiers.contains($0.identifier) }
    }

    func removeAllPendingNotificationRequests() {
        requests.removeAll()
    }
}

enum TestSupport {
    static func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Paper.self,
            Tag.self,
            UserSettings.self,
            FeedbackEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    static func reminderDate(hour: Int = 9, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
