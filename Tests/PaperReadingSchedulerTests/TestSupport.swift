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

final class SpyPaperFusionGenerator: PaperFusionGenerating, @unchecked Sendable {
    private(set) var inputs: [[PaperFusionInput]] = []
    private let handler: @Sendable ([PaperFusionInput], AIProviderConfiguration) throws -> [PaperFusionIdea]

    init(
        handler: @escaping @Sendable ([PaperFusionInput], AIProviderConfiguration) throws -> [PaperFusionIdea]
    ) {
        self.handler = handler
    }

    var callCount: Int {
        inputs.count
    }

    func generateIdeas(
        for inputs: [PaperFusionInput],
        configuration: AIProviderConfiguration
    ) async throws -> [PaperFusionIdea] {
        self.inputs.append(inputs)
        return try handler(inputs, configuration)
    }
}

final class SpyReaderAnswerer: ReaderAnswerGenerating, @unchecked Sendable {
    private(set) var inputs: [ReaderAskAIInput] = []
    private let handler: @Sendable (ReaderAskAIInput, AIProviderConfiguration) throws -> String

    init(
        handler: @escaping @Sendable (ReaderAskAIInput, AIProviderConfiguration) throws -> String
    ) {
        self.handler = handler
    }

    var callCount: Int {
        inputs.count
    }

    func answerQuestion(
        for input: ReaderAskAIInput,
        configuration: AIProviderConfiguration
    ) async throws -> String {
        inputs.append(input)
        return try handler(input, configuration)
    }
}

final class SpyPublicationEnricher: PublicationEnriching, @unchecked Sendable {
    private(set) var requests: [PublicationEnrichmentRequest] = []
    private let handler: @Sendable (PublicationEnrichmentRequest) -> PublicationEnrichmentResult

    init(
        handler: @escaping @Sendable (PublicationEnrichmentRequest) -> PublicationEnrichmentResult = { _ in
            PublicationEnrichmentResult()
        }
    ) {
        self.handler = handler
    }

    var callCount: Int {
        requests.count
    }

    func enrich(for request: PublicationEnrichmentRequest) async -> PublicationEnrichmentResult {
        requests.append(request)
        return handler(request)
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

final class FakeTextClipboard: TextClipboardWriting, @unchecked Sendable {
    private(set) var copiedStrings: [String] = []

    var lastCopiedString: String? {
        copiedStrings.last
    }

    func setString(_ string: String) {
        copiedStrings.append(string)
    }
}

struct StubReaderDocumentContextLoader: ReaderDocumentContextLoading {
    let context: ReaderAskAIDocumentContext

    func loadDocumentContext(from fileURL: URL) -> ReaderAskAIDocumentContext {
        context
    }
}

final class FakePaperStorageCredentialStore: PaperStorageCredentialStoring, @unchecked Sendable {
    var storedPasswords: [PaperStorageRemoteEndpoint: String]

    init(storedPasswords: [PaperStorageRemoteEndpoint: String] = [:]) {
        self.storedPasswords = storedPasswords
    }

    func loadPassword(for endpoint: PaperStorageRemoteEndpoint) throws -> String? {
        storedPasswords[endpoint]
    }

    func savePassword(_ password: String, for endpoint: PaperStorageRemoteEndpoint) throws {
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPassword.isEmpty {
            storedPasswords.removeValue(forKey: endpoint)
        } else {
            storedPasswords[endpoint] = trimmedPassword
        }
    }

    func deletePassword(for endpoint: PaperStorageRemoteEndpoint) throws {
        storedPasswords.removeValue(forKey: endpoint)
    }
}

struct RecordedCommandInvocation: Equatable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
    let standardInput: Data?
}

final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    private(set) var invocations: [RecordedCommandInvocation] = []
    var result = CommandResult(standardOutput: "", standardError: "", terminationStatus: 0)
    var error: Error?

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL?,
        standardInput: Data?
    ) throws -> CommandResult {
        invocations.append(
            RecordedCommandInvocation(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment,
                standardInput: standardInput
            )
        )

        if let error {
            throw error
        }

        return result
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
            PaperAnnotation.self,
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

    static func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperReadingSchedulerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
