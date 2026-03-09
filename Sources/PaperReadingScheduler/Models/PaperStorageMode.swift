import Foundation

enum PaperStorageMode: String, CaseIterable, Identifiable, Sendable {
    case defaultLocal
    case customLocal
    case remoteSSH

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultLocal:
            "Default"
        case .customLocal:
            "Local"
        case .remoteSSH:
            "Remote SSH"
        }
    }
}

struct PaperStorageRemoteEndpoint: Hashable, Equatable, Sendable {
    let host: String
    let port: Int
    let username: String

    var commandDestination: String {
        "\(username)@\(host)"
    }

    var credentialAccount: String {
        "paper-storage-password:\(username)@\(host):\(port)"
    }

    var displayName: String {
        "\(username)@\(host):\(port)"
    }
}

enum PaperStorageReadiness: Equatable, Sendable {
    case readyDefaultLocal(path: String)
    case readyCustomLocal(path: String)
    case readyRemote(endpoint: PaperStorageRemoteEndpoint, directory: String)
    case missingLocalPath
    case invalidLocalPath
    case missingRemoteHost
    case invalidRemotePort
    case missingRemoteUsername
    case missingRemoteDirectory
    case missingRemotePassword

    var isReady: Bool {
        switch self {
        case .readyDefaultLocal, .readyCustomLocal, .readyRemote:
            true
        case .missingLocalPath,
             .invalidLocalPath,
             .missingRemoteHost,
             .invalidRemotePort,
             .missingRemoteUsername,
             .missingRemoteDirectory,
             .missingRemotePassword:
            false
        }
    }

    var settingsMessage: String {
        switch self {
        case let .readyDefaultLocal(path):
            "New paper PDFs will be stored in the default folder at \(path)."
        case let .readyCustomLocal(path):
            "New paper PDFs will be stored locally at \(path)."
        case let .readyRemote(endpoint, directory):
            "New paper PDFs will be stored over SSH at \(endpoint.displayName):\(directory)."
        case .missingLocalPath:
            "Choose a local folder before using custom paper storage."
        case .invalidLocalPath:
            "The selected local paper storage folder is invalid."
        case .missingRemoteHost:
            "Enter the remote SSH host before using remote paper storage."
        case .invalidRemotePort:
            "Enter a valid SSH port number before using remote paper storage."
        case .missingRemoteUsername:
            "Enter the SSH username before using remote paper storage."
        case .missingRemoteDirectory:
            "Enter the remote storage directory before using remote paper storage."
        case .missingRemotePassword:
            "Save the SSH password before using remote paper storage."
        }
    }
}

struct PaperStorageConfiguration: Equatable, Sendable {
    enum Destination: Equatable, Sendable {
        case local(directoryURL: URL)
        case remote(endpoint: PaperStorageRemoteEndpoint, directory: String, password: String)
    }

    let destination: Destination
}

func normalizedRemoteStorageDirectory(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return "" }
    guard trimmed != "/" else { return "/" }

    let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return "/\(stripped)"
}
