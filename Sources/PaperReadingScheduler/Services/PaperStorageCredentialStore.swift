import Foundation
import Security

protocol PaperStorageCredentialStoring: Sendable {
    func loadPassword(for endpoint: PaperStorageRemoteEndpoint) throws -> String?
    func savePassword(_ password: String, for endpoint: PaperStorageRemoteEndpoint) throws
    func deletePassword(for endpoint: PaperStorageRemoteEndpoint) throws
}

enum PaperStorageCredentialStoreError: LocalizedError {
    case invalidEncoding
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            "The stored SSH password could not be read."
        case let .unhandledStatus(status):
            "The SSH password could not be updated. Keychain status: \(status)."
        }
    }
}

struct KeychainPaperStorageCredentialStore: PaperStorageCredentialStoring {
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "PaperReadingScheduler") {
        self.service = service
    }

    func loadPassword(for endpoint: PaperStorageRemoteEndpoint) throws -> String? {
        var query = baseQuery(for: endpoint)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let password = String(data: data, encoding: .utf8) else {
                throw PaperStorageCredentialStoreError.invalidEncoding
            }
            return password
        case errSecItemNotFound:
            return nil
        default:
            throw PaperStorageCredentialStoreError.unhandledStatus(status)
        }
    }

    func savePassword(_ password: String, for endpoint: PaperStorageRemoteEndpoint) throws {
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPassword.isEmpty == false else {
            try deletePassword(for: endpoint)
            return
        }

        let data = Data(trimmedPassword.utf8)
        let status = SecItemCopyMatching(baseQuery(for: endpoint) as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            let attributes = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery(for: endpoint) as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw PaperStorageCredentialStoreError.unhandledStatus(updateStatus)
            }
        case errSecItemNotFound:
            var query = baseQuery(for: endpoint)
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw PaperStorageCredentialStoreError.unhandledStatus(addStatus)
            }
        default:
            throw PaperStorageCredentialStoreError.unhandledStatus(status)
        }
    }

    func deletePassword(for endpoint: PaperStorageRemoteEndpoint) throws {
        let status = SecItemDelete(baseQuery(for: endpoint) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PaperStorageCredentialStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(for endpoint: PaperStorageRemoteEndpoint) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: endpoint.credentialAccount
        ]
    }
}

struct InMemoryPaperStorageCredentialStore: PaperStorageCredentialStoring {
    private let storedPasswords: [PaperStorageRemoteEndpoint: String]

    init(storedPasswords: [PaperStorageRemoteEndpoint: String] = [:]) {
        self.storedPasswords = storedPasswords
    }

    func loadPassword(for endpoint: PaperStorageRemoteEndpoint) throws -> String? {
        storedPasswords[endpoint]
    }

    func savePassword(_ password: String, for endpoint: PaperStorageRemoteEndpoint) throws {}

    func deletePassword(for endpoint: PaperStorageRemoteEndpoint) throws {}
}
