import Foundation
import Security

protocol TaggingCredentialStoring: Sendable {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ apiKey: String) throws
    func deleteAPIKey() throws
}

enum TaggingCredentialStoreError: LocalizedError {
    case invalidEncoding
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            "The stored AI API key could not be read."
        case let .unhandledStatus(status):
            "The AI API key could not be updated. Keychain status: \(status)."
        }
    }
}

struct KeychainTaggingCredentialStore: TaggingCredentialStoring {
    private let service: String
    private let account: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "PaperReadingScheduler",
        account: String = "ai-tagging-api-key"
    ) {
        self.service = service
        self.account = account
    }

    func loadAPIKey() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let apiKey = String(data: data, encoding: .utf8) else {
                throw TaggingCredentialStoreError.invalidEncoding
            }
            return apiKey
        case errSecItemNotFound:
            return nil
        default:
            throw TaggingCredentialStoreError.unhandledStatus(status)
        }
    }

    func saveAPIKey(_ apiKey: String) throws {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAPIKey.isEmpty == false else {
            try deleteAPIKey()
            return
        }

        let data = Data(trimmedAPIKey.utf8)
        let status = SecItemCopyMatching(baseQuery() as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            let attributes = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw TaggingCredentialStoreError.unhandledStatus(updateStatus)
            }
        case errSecItemNotFound:
            var query = baseQuery()
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw TaggingCredentialStoreError.unhandledStatus(addStatus)
            }
        default:
            throw TaggingCredentialStoreError.unhandledStatus(status)
        }
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TaggingCredentialStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
