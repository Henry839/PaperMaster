import Foundation

struct CommandResult: Equatable, Sendable {
    let standardOutput: String
    let standardError: String
    let terminationStatus: Int32
}

protocol CommandRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL?,
        standardInput: Data?
    ) throws -> CommandResult
}

enum CommandRunnerError: LocalizedError {
    case nonZeroExit(executablePath: String, status: Int32, standardError: String)

    var errorDescription: String? {
        switch self {
        case let .nonZeroExit(executablePath, status, standardError):
            let trimmedError = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedError.isEmpty {
                return "\(executablePath) exited with status \(status)."
            }
            return "\(executablePath) exited with status \(status): \(trimmedError)"
        }
    }
}

struct ProcessCommandRunner: CommandRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:],
        currentDirectoryURL: URL? = nil,
        standardInput: Data? = nil
    ) throws -> CommandResult {
        let process = Process()
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, newValue in
            newValue
        }
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe

        let standardInputPipe: Pipe?
        if standardInput != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            standardInputPipe = pipe
        } else {
            standardInputPipe = nil
        }

        try process.run()

        if let standardInput, let standardInputPipe {
            standardInputPipe.fileHandleForWriting.write(standardInput)
            try? standardInputPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()

        let standardOutput = String(
            data: standardOutputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let standardError = String(
            data: standardErrorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let result = CommandResult(
            standardOutput: standardOutput,
            standardError: standardError,
            terminationStatus: process.terminationStatus
        )

        guard process.terminationStatus == 0 else {
            throw CommandRunnerError.nonZeroExit(
                executablePath: executableURL.path,
                status: process.terminationStatus,
                standardError: standardError
            )
        }

        return result
    }
}

enum ManagedPaperStorageLocation: Equatable, Sendable {
    case local(URL)
    case remote(URL)
}

enum PaperStorageServiceError: LocalizedError {
    case missingPDFURL
    case invalidConfiguration(String)
    case invalidManagedRemoteURL
    case missingRemotePassword(PaperStorageRemoteEndpoint)

    var errorDescription: String? {
        switch self {
        case .missingPDFURL:
            "This paper does not have a PDF URL to store."
        case let .invalidConfiguration(message):
            message
        case .invalidManagedRemoteURL:
            "The saved remote paper storage URL is invalid."
        case let .missingRemotePassword(endpoint):
            "No SSH password was saved for \(endpoint.displayName)."
        }
    }
}

struct ManagedRemotePaperLocation: Equatable, Sendable {
    let endpoint: PaperStorageRemoteEndpoint
    let remotePath: String
}

struct PaperStorageService: Sendable {
    let networking: Networking
    let credentialStore: PaperStorageCredentialStoring
    let commandRunner: CommandRunning
    let fileManager: FileManager
    let defaultStorageDirectoryURL: URL
    let temporaryRootDirectoryURL: URL

    init(
        networking: Networking = URLSessionNetworking(),
        credentialStore: PaperStorageCredentialStoring = InMemoryPaperStorageCredentialStore(),
        commandRunner: CommandRunning = ProcessCommandRunner(),
        fileManager: FileManager = .default,
        defaultStorageDirectoryURL: URL? = nil,
        temporaryRootDirectoryURL: URL? = nil
    ) {
        self.networking = networking
        self.credentialStore = credentialStore
        self.commandRunner = commandRunner
        self.fileManager = fileManager
        let fallbackDefaultDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PaperMaster", isDirectory: true)
            .appendingPathComponent("Papers", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("PaperMaster", isDirectory: true)
                .appendingPathComponent("Papers", isDirectory: true)
        self.defaultStorageDirectoryURL = defaultStorageDirectoryURL ?? fallbackDefaultDirectory
        self.temporaryRootDirectoryURL = temporaryRootDirectoryURL
            ?? fileManager.temporaryDirectory.appendingPathComponent("PaperMasterPaperStorage", isDirectory: true)
    }

    @MainActor
    func storeManagedPDF(for paper: Paper, settings: UserSettings) async throws -> ManagedPaperStorageLocation {
        guard let pdfURL = paper.pdfURL else {
            throw PaperStorageServiceError.missingPDFURL
        }

        let remotePassword = try remotePasswordIfNeeded(for: settings)
        guard let configuration = settings.paperStorageConfiguration(
            defaultDirectoryURL: defaultStorageDirectoryURL,
            remotePassword: remotePassword
        ) else {
            let readiness = settings.paperStorageReadiness(
                defaultDirectoryURL: defaultStorageDirectoryURL,
                hasRemotePassword: remotePassword?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            )
            throw PaperStorageServiceError.invalidConfiguration(readiness.settingsMessage)
        }

        return try await storeManagedPDF(
            from: pdfURL,
            paperID: paper.id,
            title: paper.title,
            configuration: configuration
        )
    }

    @MainActor
    func storeManagedLocalPDF(
        from sourceFileURL: URL,
        for paper: Paper,
        settings: UserSettings
    ) async throws -> ManagedPaperStorageLocation {
        let remotePassword = try remotePasswordIfNeeded(for: settings)
        guard let configuration = settings.paperStorageConfiguration(
            defaultDirectoryURL: defaultStorageDirectoryURL,
            remotePassword: remotePassword
        ) else {
            let readiness = settings.paperStorageReadiness(
                defaultDirectoryURL: defaultStorageDirectoryURL,
                hasRemotePassword: remotePassword?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            )
            throw PaperStorageServiceError.invalidConfiguration(readiness.settingsMessage)
        }

        return try await storeManagedLocalPDF(
            from: sourceFileURL,
            paperID: paper.id,
            title: paper.title,
            configuration: configuration
        )
    }

    func storeManagedPDF(
        from pdfURL: URL,
        paperID: UUID,
        title: String,
        configuration: PaperStorageConfiguration
    ) async throws -> ManagedPaperStorageLocation {
        let (data, _) = try await networking.data(from: pdfURL)
        let filename = managedFilename(paperID: paperID, title: title)

        switch configuration.destination {
        case let .local(directoryURL):
            let storedURL = try await writeLocalManagedPDF(
                data: data,
                directoryURL: directoryURL,
                filename: filename
            )
            return .local(storedURL)
        case let .remote(endpoint, directory, password):
            let remoteURL = try await uploadManagedPDF(
                data: data,
                endpoint: endpoint,
                remoteDirectory: directory,
                filename: filename,
                password: password
            )
            return .remote(remoteURL)
        }
    }

    func storeManagedLocalPDF(
        from sourceFileURL: URL,
        paperID: UUID,
        title: String,
        configuration: PaperStorageConfiguration
    ) async throws -> ManagedPaperStorageLocation {
        let filename = managedFilename(paperID: paperID, title: title)

        switch configuration.destination {
        case let .local(directoryURL):
            let storedURL = try await importLocalManagedPDF(
                from: sourceFileURL,
                directoryURL: directoryURL,
                filename: filename
            )
            return .local(storedURL)
        case let .remote(endpoint, directory, password):
            let data = try Data(contentsOf: sourceFileURL)
            let remoteURL = try await uploadManagedPDF(
                data: data,
                endpoint: endpoint,
                remoteDirectory: directory,
                filename: filename,
                password: password
            )
            return .remote(remoteURL)
        }
    }

    @MainActor
    func materializeRemoteManagedPDF(
        for paper: Paper,
        cacheDirectoryURL: URL
    ) async throws -> URL {
        guard let remoteURL = paper.managedPDFRemoteURL else {
            throw PaperStorageServiceError.invalidManagedRemoteURL
        }

        return try await materializeRemoteManagedPDF(
            from: remoteURL,
            cacheDirectoryURL: cacheDirectoryURL
        )
    }

    func materializeRemoteManagedPDF(
        from remoteURL: URL,
        cacheDirectoryURL: URL
    ) async throws -> URL {
        guard let location = managedRemoteLocation(from: remoteURL) else {
            throw PaperStorageServiceError.invalidManagedRemoteURL
        }

        guard let password = try credentialStore.loadPassword(for: location.endpoint),
              password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw PaperStorageServiceError.missingRemotePassword(location.endpoint)
        }

        try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        let destinationURL = cacheDirectoryURL.appendingPathComponent(remoteURL.lastPathComponent)

        try await withAskPassEnvironment(password: password) { environment in
            try runCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/sftp"),
                arguments: sftpBaseArguments(for: location.endpoint),
                environment: environment,
                standardInput: Data(
                    "get \(quotedSFTPArgument(location.remotePath)) \(quotedSFTPArgument(destinationURL.path))\n".utf8
                )
            )
        }

        return destinationURL
    }

    @MainActor
    func removeManagedPDF(for paper: Paper) async throws {
        try await removeManagedPDF(
            localURL: paper.managedPDFLocalURL,
            remoteURL: paper.managedPDFRemoteURL
        )
    }

    func removeManagedPDF(localURL: URL?, remoteURL: URL?) async throws {
        if let localURL {
            if fileManager.fileExists(atPath: localURL.path) {
                try fileManager.removeItem(at: localURL)
            }
            return
        }

        guard let remoteURL,
              let location = managedRemoteLocation(from: remoteURL),
              let password = try credentialStore.loadPassword(for: location.endpoint),
              password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }

        try await withAskPassEnvironment(password: password) { environment in
            try runCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/sftp"),
                arguments: sftpBaseArguments(for: location.endpoint),
                environment: environment,
                standardInput: Data("rm \(quotedSFTPArgument(location.remotePath))\n".utf8)
            )
        }
    }

    @MainActor
    func managedFilename(for paper: Paper) -> String {
        managedFilename(paperID: paper.id, title: paper.title)
    }

    func managedFilename(paperID: UUID, title: String) -> String {
        let shortID = String(paperID.uuidString.prefix(8)).lowercased()
        let sanitizedTitle = sanitizedFilenameBase(for: title, fallback: "paper")
        return "\(sanitizedTitle)-\(shortID).pdf"
    }

    func managedRemoteLocation(from remoteURL: URL) -> ManagedRemotePaperLocation? {
        guard remoteURL.scheme?.lowercased() == "sftp",
              let host = remoteURL.host,
              let username = remoteURL.user else {
            return nil
        }

        let decodedPath = remoteURL.path.removingPercentEncoding ?? remoteURL.path
        guard decodedPath.isEmpty == false else { return nil }

        return ManagedRemotePaperLocation(
            endpoint: PaperStorageRemoteEndpoint(
                host: host,
                port: remoteURL.port ?? 22,
                username: username
            ),
            remotePath: decodedPath
        )
    }

    private func remotePasswordIfNeeded(for settings: UserSettings) throws -> String? {
        guard settings.paperStorageMode == .remoteSSH,
              let endpoint = settings.paperStorageCredentialEndpoint else {
            return nil
        }
        return try credentialStore.loadPassword(for: endpoint)
    }

    private func writeLocalManagedPDF(
        data: Data,
        directoryURL: URL,
        filename: String
    ) async throws -> URL {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        let destinationURL = directoryURL.appendingPathComponent(filename)
        try await Task.detached(priority: .utility) {
            try data.write(to: destinationURL, options: [.atomic])
        }.value
        return destinationURL
    }

    private func importLocalManagedPDF(
        from sourceFileURL: URL,
        directoryURL: URL,
        filename: String
    ) async throws -> URL {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)

        let standardizedSourceURL = sourceFileURL.standardizedFileURL
        let destinationURL = directoryURL.appendingPathComponent(filename)
        let standardizedDestinationURL = destinationURL.standardizedFileURL

        if standardizedSourceURL == standardizedDestinationURL {
            return destinationURL
        }

        if standardizedSourceURL.deletingLastPathComponent() == directoryURL.standardizedFileURL {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: sourceFileURL, to: destinationURL)
            return destinationURL
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceFileURL, to: destinationURL)
        return destinationURL
    }

    private func uploadManagedPDF(
        data: Data,
        endpoint: PaperStorageRemoteEndpoint,
        remoteDirectory: String,
        filename: String,
        password: String
    ) async throws -> URL {
        try fileManager.createDirectory(at: temporaryRootDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        let temporaryDirectoryURL = temporaryRootDirectoryURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        defer {
            try? fileManager.removeItem(at: temporaryDirectoryURL)
        }

        let localFileURL = temporaryDirectoryURL.appendingPathComponent(filename)
        try data.write(to: localFileURL, options: [.atomic])

        let remotePath = remoteFilePath(directory: remoteDirectory, filename: filename)
        try await withAskPassEnvironment(password: password) { environment in
            try runCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
                arguments: sshBaseArguments(for: endpoint) + [
                    "mkdir -p -- \(quotedShellArgument(remoteDirectory))"
                ],
                environment: environment,
                standardInput: nil
            )

            try runCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/sftp"),
                arguments: sftpBaseArguments(for: endpoint),
                environment: environment,
                standardInput: Data(
                    "put \(quotedSFTPArgument(localFileURL.path)) \(quotedSFTPArgument(remotePath))\n".utf8
                )
            )
        }

        return remoteSnapshotURL(endpoint: endpoint, remotePath: remotePath)
    }

    private func remoteSnapshotURL(
        endpoint: PaperStorageRemoteEndpoint,
        remotePath: String
    ) -> URL {
        var components = URLComponents()
        components.scheme = "sftp"
        components.user = endpoint.username
        components.host = endpoint.host
        components.port = endpoint.port
        components.path = remotePath.hasPrefix("/") ? remotePath : "/\(remotePath)"
        return components.url!
    }

    private func remoteFilePath(directory: String, filename: String) -> String {
        let normalizedDirectory = normalizedRemoteStorageDirectory(directory)
        guard normalizedDirectory != "/" else {
            return "/\(filename)"
        }
        return "\(normalizedDirectory)/\(filename)"
    }

    private func runCommand(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        standardInput: Data?
    ) throws {
        _ = try commandRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            currentDirectoryURL: nil,
            standardInput: standardInput
        )
    }

    private func sshBaseArguments(for endpoint: PaperStorageRemoteEndpoint) -> [String] {
        [
            "-p", String(endpoint.port),
            "-o", "BatchMode=no",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "PreferredAuthentications=password",
            "-o", "PubkeyAuthentication=no",
            "-o", "StrictHostKeyChecking=accept-new",
            endpoint.commandDestination
        ]
    }

    private func sftpBaseArguments(for endpoint: PaperStorageRemoteEndpoint) -> [String] {
        [
            "-P", String(endpoint.port),
            "-o", "BatchMode=no",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "PreferredAuthentications=password",
            "-o", "PubkeyAuthentication=no",
            "-o", "StrictHostKeyChecking=accept-new",
            endpoint.commandDestination
        ]
    }

    private func withAskPassEnvironment<T>(
        password: String,
        operation: @Sendable ([String: String]) async throws -> T
    ) async throws -> T {
        try fileManager.createDirectory(at: temporaryRootDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        let askPassScriptURL = temporaryRootDirectoryURL.appendingPathComponent("askpass-\(UUID().uuidString).sh")
        let scriptContents = """
        #!/bin/sh
        printf '%s\\n' "$PAPER_STORAGE_PASSWORD"
        """

        try scriptContents.write(to: askPassScriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askPassScriptURL.path)

        defer {
            try? fileManager.removeItem(at: askPassScriptURL)
        }

        return try await operation([
            "SSH_ASKPASS": askPassScriptURL.path,
            "SSH_ASKPASS_REQUIRE": "force",
            "DISPLAY": "henrypaper-storage",
            "PAPER_STORAGE_PASSWORD": password
        ])
    }

    private func sanitizedFilenameBase(for title: String, fallback: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmedTitle.isEmpty ? fallback : trimmedTitle
        let allowedScalars = CharacterSet.alphanumerics.union(.whitespaces)
        let cleaned = base.unicodeScalars.map { scalar in
            allowedScalars.contains(scalar) ? String(scalar) : "-"
        }
        .joined()

        var collapsed = cleaned.replacingOccurrences(of: " ", with: "-")
        while collapsed.contains("--") {
            collapsed = collapsed.replacingOccurrences(of: "--", with: "-")
        }
        collapsed = collapsed
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()

        return collapsed.isEmpty ? fallback : collapsed
    }

    private func quotedShellArgument(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func quotedSFTPArgument(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
