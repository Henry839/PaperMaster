import Foundation
#if PAPERMASTER_LEGACY_MODE
import Combine
#else
import SwiftData
#endif

#if PAPERMASTER_LEGACY_MODE
final class UserSettings: ObservableObject, Identifiable {
    let id: UUID
    @Published var papersPerDay: Int
    @Published var dailyReminderTime: Date
    @Published var autoCachePDFs: Bool
    @Published var defaultImportBehaviorRawValue: String
    @Published var paperStorageModeRawValueStorage: String?
    @Published var customPaperStoragePathStorage: String?
    @Published var remotePaperStorageHostStorage: String?
    @Published var remotePaperStoragePortStorage: Int?
    @Published var remotePaperStorageUsernameStorage: String?
    @Published var remotePaperStorageDirectoryStorage: String?
    @Published var aiTaggingEnabled: Bool
    @Published var aiTaggingBaseURLString: String
    @Published var aiTaggingModel: String

    init(
        id: UUID = UUID(),
        papersPerDay: Int = 1,
        dailyReminderTime: Date = UserSettings.defaultReminderDate(),
        autoCachePDFs: Bool = false,
        defaultImportBehavior: ImportBehavior = .scheduleImmediately,
        paperStorageMode: PaperStorageMode = .defaultLocal,
        customPaperStoragePath: String = "",
        remotePaperStorageHost: String = "",
        remotePaperStoragePort: Int = 22,
        remotePaperStorageUsername: String = "",
        remotePaperStorageDirectory: String = "",
        aiTaggingEnabled: Bool = false,
        aiTaggingBaseURLString: String = "https://api.openai.com/v1",
        aiTaggingModel: String = "gpt-4o-mini"
    ) {
        self.id = id
        self.papersPerDay = papersPerDay
        self.dailyReminderTime = dailyReminderTime
        self.autoCachePDFs = autoCachePDFs
        self.defaultImportBehaviorRawValue = defaultImportBehavior.rawValue
        self.paperStorageModeRawValueStorage = paperStorageMode.rawValue
        self.customPaperStoragePathStorage = customPaperStoragePath
        self.remotePaperStorageHostStorage = remotePaperStorageHost
        self.remotePaperStoragePortStorage = remotePaperStoragePort
        self.remotePaperStorageUsernameStorage = remotePaperStorageUsername
        self.remotePaperStorageDirectoryStorage = remotePaperStorageDirectory
        self.aiTaggingEnabled = aiTaggingEnabled
        self.aiTaggingBaseURLString = aiTaggingBaseURLString
        self.aiTaggingModel = aiTaggingModel
    }

    convenience init(snapshot: UserSettingsSnapshot) {
        self.init(
            id: snapshot.id,
            papersPerDay: snapshot.papersPerDay,
            dailyReminderTime: snapshot.dailyReminderTime,
            autoCachePDFs: snapshot.autoCachePDFs,
            defaultImportBehavior: ImportBehavior(rawValue: snapshot.defaultImportBehaviorRawValue) ?? .scheduleImmediately,
            paperStorageMode: PaperStorageMode(rawValue: snapshot.paperStorageModeRawValueStorage ?? "") ?? .defaultLocal,
            customPaperStoragePath: snapshot.customPaperStoragePathStorage ?? "",
            remotePaperStorageHost: snapshot.remotePaperStorageHostStorage ?? "",
            remotePaperStoragePort: snapshot.remotePaperStoragePortStorage ?? 22,
            remotePaperStorageUsername: snapshot.remotePaperStorageUsernameStorage ?? "",
            remotePaperStorageDirectory: snapshot.remotePaperStorageDirectoryStorage ?? "",
            aiTaggingEnabled: snapshot.aiTaggingEnabled,
            aiTaggingBaseURLString: snapshot.aiTaggingBaseURLString,
            aiTaggingModel: snapshot.aiTaggingModel
        )
    }

    var snapshot: UserSettingsSnapshot {
        UserSettingsSnapshot(
            id: id,
            papersPerDay: papersPerDay,
            dailyReminderTime: dailyReminderTime,
            autoCachePDFs: autoCachePDFs,
            defaultImportBehaviorRawValue: defaultImportBehaviorRawValue,
            paperStorageModeRawValueStorage: paperStorageModeRawValueStorage,
            customPaperStoragePathStorage: customPaperStoragePathStorage,
            remotePaperStorageHostStorage: remotePaperStorageHostStorage,
            remotePaperStoragePortStorage: remotePaperStoragePortStorage,
            remotePaperStorageUsernameStorage: remotePaperStorageUsernameStorage,
            remotePaperStorageDirectoryStorage: remotePaperStorageDirectoryStorage,
            aiTaggingEnabled: aiTaggingEnabled,
            aiTaggingBaseURLString: aiTaggingBaseURLString,
            aiTaggingModel: aiTaggingModel
        )
    }

    var defaultImportBehavior: ImportBehavior {
        get { ImportBehavior(rawValue: defaultImportBehaviorRawValue) ?? .scheduleImmediately }
        set { defaultImportBehaviorRawValue = newValue.rawValue }
    }

    var paperStorageMode: PaperStorageMode {
        get { PaperStorageMode(rawValue: paperStorageModeRawValueStorage ?? "") ?? .defaultLocal }
        set { paperStorageModeRawValueStorage = newValue.rawValue }
    }

    var customPaperStoragePath: String {
        get { customPaperStoragePathStorage ?? "" }
        set { customPaperStoragePathStorage = newValue }
    }

    var remotePaperStorageHost: String {
        get { remotePaperStorageHostStorage ?? "" }
        set { remotePaperStorageHostStorage = newValue }
    }

    var remotePaperStoragePort: Int {
        get { remotePaperStoragePortStorage ?? 22 }
        set { remotePaperStoragePortStorage = newValue }
    }

    var remotePaperStorageUsername: String {
        get { remotePaperStorageUsernameStorage ?? "" }
        set { remotePaperStorageUsernameStorage = newValue }
    }

    var remotePaperStorageDirectory: String {
        get { remotePaperStorageDirectoryStorage ?? "" }
        set { remotePaperStorageDirectoryStorage = newValue }
    }

    func paperStorageReadiness(
        defaultDirectoryURL: URL,
        hasRemotePassword: Bool
    ) -> PaperStorageReadiness {
        switch paperStorageMode {
        case .defaultLocal:
            return .readyDefaultLocal(path: defaultDirectoryURL.path)
        case .customLocal:
            let trimmedPath = customPaperStoragePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedPath.isEmpty == false else {
                return .missingLocalPath
            }
            let localURL = URL(fileURLWithPath: trimmedPath, isDirectory: true)
            guard localURL.path.isEmpty == false else {
                return .invalidLocalPath
            }
            return .readyCustomLocal(path: localURL.path)
        case .remoteSSH:
            let trimmedHost = remotePaperStorageHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedHost.isEmpty == false else {
                return .missingRemoteHost
            }
            guard remotePaperStoragePort > 0 else {
                return .invalidRemotePort
            }
            let trimmedUsername = remotePaperStorageUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedUsername.isEmpty == false else {
                return .missingRemoteUsername
            }
            let normalizedDirectory = normalizedRemoteStorageDirectory(remotePaperStorageDirectory)
            guard normalizedDirectory.isEmpty == false else {
                return .missingRemoteDirectory
            }
            guard hasRemotePassword else {
                return .missingRemotePassword
            }
            return .readyRemote(
                endpoint: PaperStorageRemoteEndpoint(
                    host: trimmedHost,
                    port: remotePaperStoragePort,
                    username: trimmedUsername
                ),
                directory: normalizedDirectory
            )
        }
    }

    func paperStorageConfiguration(
        defaultDirectoryURL: URL,
        remotePassword: String?
    ) -> PaperStorageConfiguration? {
        switch paperStorageMode {
        case .defaultLocal:
            return PaperStorageConfiguration(destination: .local(directoryURL: defaultDirectoryURL))
        case .customLocal:
            let trimmedPath = customPaperStoragePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedPath.isEmpty == false else { return nil }
            return PaperStorageConfiguration(
                destination: .local(directoryURL: URL(fileURLWithPath: trimmedPath, isDirectory: true))
            )
        case .remoteSSH:
            let trimmedHost = remotePaperStorageHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedUsername = remotePaperStorageUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedDirectory = normalizedRemoteStorageDirectory(remotePaperStorageDirectory)
            let trimmedPassword = remotePassword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard trimmedHost.isEmpty == false,
                  remotePaperStoragePort > 0,
                  trimmedUsername.isEmpty == false,
                  normalizedDirectory.isEmpty == false,
                  trimmedPassword.isEmpty == false else {
                return nil
            }
            return PaperStorageConfiguration(
                destination: .remote(
                    endpoint: PaperStorageRemoteEndpoint(
                        host: trimmedHost,
                        port: remotePaperStoragePort,
                        username: trimmedUsername
                    ),
                    directory: normalizedDirectory,
                    password: trimmedPassword
                )
            )
        }
    }

    var paperStorageCredentialEndpoint: PaperStorageRemoteEndpoint? {
        let trimmedHost = remotePaperStorageHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = remotePaperStorageUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedHost.isEmpty == false,
              remotePaperStoragePort > 0,
              trimmedUsername.isEmpty == false else {
            return nil
        }

        return PaperStorageRemoteEndpoint(
            host: trimmedHost,
            port: remotePaperStoragePort,
            username: trimmedUsername
        )
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

    func aiProviderReadiness(apiKey: String?) -> AIProviderReadiness {
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
            AIProviderConfiguration(
                baseURL: baseURL,
                model: trimmedModel,
                apiKey: trimmedAPIKey
            )
        )
    }

    func aiProviderConfiguration(apiKey: String?) -> AIProviderConfiguration? {
        aiProviderReadiness(apiKey: apiKey).configuration
    }

    func aiTaggingReadiness(apiKey: String?) -> AITaggingReadiness {
        guard aiTaggingEnabled else { return .disabled }

        switch aiProviderReadiness(apiKey: apiKey) {
        case .missingBaseURL:
            return .missingBaseURL
        case .invalidBaseURL:
            return .invalidBaseURL
        case .missingModel:
            return .missingModel
        case .missingAPIKey:
            return .missingAPIKey
        case let .ready(configuration):
            return .ready(configuration)
        }
    }

    func aiTaggingConfiguration(apiKey: String?) -> PaperTaggingConfiguration? {
        guard case let .ready(configuration) = aiTaggingReadiness(apiKey: apiKey) else {
            return nil
        }
        return configuration
    }
}

struct UserSettingsSnapshot: Codable {
    let id: UUID
    let papersPerDay: Int
    let dailyReminderTime: Date
    let autoCachePDFs: Bool
    let defaultImportBehaviorRawValue: String
    let paperStorageModeRawValueStorage: String?
    let customPaperStoragePathStorage: String?
    let remotePaperStorageHostStorage: String?
    let remotePaperStoragePortStorage: Int?
    let remotePaperStorageUsernameStorage: String?
    let remotePaperStorageDirectoryStorage: String?
    let aiTaggingEnabled: Bool
    let aiTaggingBaseURLString: String
    let aiTaggingModel: String
}
#else
@Model
final class UserSettings {
    @Attribute(.unique) var id: UUID
    var papersPerDay: Int
    var dailyReminderTime: Date
    var autoCachePDFs: Bool
    var defaultImportBehaviorRawValue: String
    var paperStorageModeRawValueStorage: String?
    var customPaperStoragePathStorage: String?
    var remotePaperStorageHostStorage: String?
    var remotePaperStoragePortStorage: Int?
    var remotePaperStorageUsernameStorage: String?
    var remotePaperStorageDirectoryStorage: String?
    var aiTaggingEnabled: Bool
    var aiTaggingBaseURLString: String
    var aiTaggingModel: String

    init(
        id: UUID = UUID(),
        papersPerDay: Int = 1,
        dailyReminderTime: Date = UserSettings.defaultReminderDate(),
        autoCachePDFs: Bool = false,
        defaultImportBehavior: ImportBehavior = .scheduleImmediately,
        paperStorageMode: PaperStorageMode = .defaultLocal,
        customPaperStoragePath: String = "",
        remotePaperStorageHost: String = "",
        remotePaperStoragePort: Int = 22,
        remotePaperStorageUsername: String = "",
        remotePaperStorageDirectory: String = "",
        aiTaggingEnabled: Bool = false,
        aiTaggingBaseURLString: String = "https://api.openai.com/v1",
        aiTaggingModel: String = "gpt-4o-mini"
    ) {
        self.id = id
        self.papersPerDay = papersPerDay
        self.dailyReminderTime = dailyReminderTime
        self.autoCachePDFs = autoCachePDFs
        self.defaultImportBehaviorRawValue = defaultImportBehavior.rawValue
        self.paperStorageModeRawValueStorage = paperStorageMode.rawValue
        self.customPaperStoragePathStorage = customPaperStoragePath
        self.remotePaperStorageHostStorage = remotePaperStorageHost
        self.remotePaperStoragePortStorage = remotePaperStoragePort
        self.remotePaperStorageUsernameStorage = remotePaperStorageUsername
        self.remotePaperStorageDirectoryStorage = remotePaperStorageDirectory
        self.aiTaggingEnabled = aiTaggingEnabled
        self.aiTaggingBaseURLString = aiTaggingBaseURLString
        self.aiTaggingModel = aiTaggingModel
    }

    var defaultImportBehavior: ImportBehavior {
        get { ImportBehavior(rawValue: defaultImportBehaviorRawValue) ?? .scheduleImmediately }
        set { defaultImportBehaviorRawValue = newValue.rawValue }
    }

    var paperStorageMode: PaperStorageMode {
        get { PaperStorageMode(rawValue: paperStorageModeRawValueStorage ?? "") ?? .defaultLocal }
        set { paperStorageModeRawValueStorage = newValue.rawValue }
    }

    var customPaperStoragePath: String {
        get { customPaperStoragePathStorage ?? "" }
        set { customPaperStoragePathStorage = newValue }
    }

    var remotePaperStorageHost: String {
        get { remotePaperStorageHostStorage ?? "" }
        set { remotePaperStorageHostStorage = newValue }
    }

    var remotePaperStoragePort: Int {
        get { remotePaperStoragePortStorage ?? 22 }
        set { remotePaperStoragePortStorage = newValue }
    }

    var remotePaperStorageUsername: String {
        get { remotePaperStorageUsernameStorage ?? "" }
        set { remotePaperStorageUsernameStorage = newValue }
    }

    var remotePaperStorageDirectory: String {
        get { remotePaperStorageDirectoryStorage ?? "" }
        set { remotePaperStorageDirectoryStorage = newValue }
    }

    func paperStorageReadiness(
        defaultDirectoryURL: URL,
        hasRemotePassword: Bool
    ) -> PaperStorageReadiness {
        switch paperStorageMode {
        case .defaultLocal:
            return .readyDefaultLocal(path: defaultDirectoryURL.path)
        case .customLocal:
            let trimmedPath = customPaperStoragePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedPath.isEmpty == false else {
                return .missingLocalPath
            }
            let localURL = URL(fileURLWithPath: trimmedPath, isDirectory: true)
            guard localURL.path.isEmpty == false else {
                return .invalidLocalPath
            }
            return .readyCustomLocal(path: localURL.path)
        case .remoteSSH:
            let trimmedHost = remotePaperStorageHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedHost.isEmpty == false else {
                return .missingRemoteHost
            }
            guard remotePaperStoragePort > 0 else {
                return .invalidRemotePort
            }
            let trimmedUsername = remotePaperStorageUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedUsername.isEmpty == false else {
                return .missingRemoteUsername
            }
            let normalizedDirectory = normalizedRemoteStorageDirectory(remotePaperStorageDirectory)
            guard normalizedDirectory.isEmpty == false else {
                return .missingRemoteDirectory
            }
            guard hasRemotePassword else {
                return .missingRemotePassword
            }
            return .readyRemote(
                endpoint: PaperStorageRemoteEndpoint(
                    host: trimmedHost,
                    port: remotePaperStoragePort,
                    username: trimmedUsername
                ),
                directory: normalizedDirectory
            )
        }
    }

    func paperStorageConfiguration(
        defaultDirectoryURL: URL,
        remotePassword: String?
    ) -> PaperStorageConfiguration? {
        switch paperStorageMode {
        case .defaultLocal:
            return PaperStorageConfiguration(destination: .local(directoryURL: defaultDirectoryURL))
        case .customLocal:
            let trimmedPath = customPaperStoragePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedPath.isEmpty == false else { return nil }
            return PaperStorageConfiguration(
                destination: .local(directoryURL: URL(fileURLWithPath: trimmedPath, isDirectory: true))
            )
        case .remoteSSH:
            let trimmedHost = remotePaperStorageHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedUsername = remotePaperStorageUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedDirectory = normalizedRemoteStorageDirectory(remotePaperStorageDirectory)
            let trimmedPassword = remotePassword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard trimmedHost.isEmpty == false,
                  remotePaperStoragePort > 0,
                  trimmedUsername.isEmpty == false,
                  normalizedDirectory.isEmpty == false,
                  trimmedPassword.isEmpty == false else {
                return nil
            }
            return PaperStorageConfiguration(
                destination: .remote(
                    endpoint: PaperStorageRemoteEndpoint(
                        host: trimmedHost,
                        port: remotePaperStoragePort,
                        username: trimmedUsername
                    ),
                    directory: normalizedDirectory,
                    password: trimmedPassword
                )
            )
        }
    }

    var paperStorageCredentialEndpoint: PaperStorageRemoteEndpoint? {
        let trimmedHost = remotePaperStorageHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = remotePaperStorageUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedHost.isEmpty == false,
              remotePaperStoragePort > 0,
              trimmedUsername.isEmpty == false else {
            return nil
        }

        return PaperStorageRemoteEndpoint(
            host: trimmedHost,
            port: remotePaperStoragePort,
            username: trimmedUsername
        )
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

    func aiProviderReadiness(apiKey: String?) -> AIProviderReadiness {
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
            AIProviderConfiguration(
                baseURL: baseURL,
                model: trimmedModel,
                apiKey: trimmedAPIKey
            )
        )
    }

    func aiProviderConfiguration(apiKey: String?) -> AIProviderConfiguration? {
        aiProviderReadiness(apiKey: apiKey).configuration
    }

    func aiTaggingReadiness(apiKey: String?) -> AITaggingReadiness {
        guard aiTaggingEnabled else { return .disabled }

        switch aiProviderReadiness(apiKey: apiKey) {
        case .missingBaseURL:
            return .missingBaseURL
        case .invalidBaseURL:
            return .invalidBaseURL
        case .missingModel:
            return .missingModel
        case .missingAPIKey:
            return .missingAPIKey
        case let .ready(configuration):
            return .ready(configuration)
        }
    }

    func aiTaggingConfiguration(apiKey: String?) -> PaperTaggingConfiguration? {
        guard case let .ready(configuration) = aiTaggingReadiness(apiKey: apiKey) else {
            return nil
        }
        return configuration
    }
}
#endif
