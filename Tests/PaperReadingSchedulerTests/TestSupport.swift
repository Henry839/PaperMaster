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

struct StubHTTPNetworking: HTTPNetworking {
    let handler: @Sendable (URLRequest) throws -> (Data, URLResponse)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try handler(request)
    }
}

struct StubMetadataResolver: MetadataResolving {
    var metadata: ResolvedPaperMetadata

    func resolve(url: URL) async throws -> ResolvedPaperMetadata {
        metadata
    }
}

final class SpyPaperTagger: PaperTagGenerating, @unchecked Sendable {
    private(set) var inputs: [PaperTaggingInput] = []
    private let handler: @Sendable (PaperTaggingInput, PaperTaggingConfiguration) throws -> [String]

    init(handler: @escaping @Sendable (PaperTaggingInput, PaperTaggingConfiguration) throws -> [String]) {
        self.handler = handler
    }

    var callCount: Int {
        inputs.count
    }

    func generateTags(
        for input: PaperTaggingInput,
        configuration: PaperTaggingConfiguration
    ) async throws -> [String] {
        inputs.append(input)
        return try handler(input, configuration)
    }
}

final class FakeTaggingCredentialStore: TaggingCredentialStoring, @unchecked Sendable {
    var apiKey: String?

    init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    func loadAPIKey() throws -> String? {
        apiKey
    }

    func saveAPIKey(_ apiKey: String) throws {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = trimmedAPIKey.isEmpty ? nil : trimmedAPIKey
    }

    func deleteAPIKey() throws {
        apiKey = nil
    }
}

struct TestError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
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

    static func httpResponse(
        url: URL = URL(string: "https://example.com")!,
        statusCode: Int = 200
    ) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }
}
