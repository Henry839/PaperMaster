import Foundation
import XCTest
@testable import PaperMaster

@MainActor
final class PaperStorageServiceTests: XCTestCase {
    func testManagedFilenameUsesSanitizedTitleAndShortID() {
        let paper = Paper(id: UUID(uuidString: "12345678-90AB-CDEF-1234-567890ABCDEF")!, title: "Agents & Tools")
        let service = PaperStorageService()

        XCTAssertEqual(service.managedFilename(for: paper), "agents-tools-12345678.pdf")
    }

    func testStoreManagedPDFWritesToCustomLocalDirectory() async throws {
        let storageDirectoryURL = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectoryURL) }

        let pdfURL = URL(string: "https://example.com/local-paper.pdf")!
        let paper = Paper(title: "Local Paper", pdfURL: pdfURL)
        let settings = UserSettings(
            paperStorageMode: .customLocal,
            customPaperStoragePath: storageDirectoryURL.path
        )
        let service = PaperStorageService(
            networking: StubNetworking { url in
                XCTAssertEqual(url, pdfURL)
                return (Data("local-pdf".utf8), TestSupport.httpResponse(url: url))
            },
            defaultStorageDirectoryURL: storageDirectoryURL
        )

        let location = try await service.storeManagedPDF(for: paper, settings: settings)

        guard case let .local(storedURL) = location else {
            return XCTFail("Expected a local managed storage location")
        }

        XCTAssertEqual(storedURL.deletingLastPathComponent().path, storageDirectoryURL.path)
        XCTAssertTrue(storedURL.lastPathComponent.hasPrefix("local-paper-"))
        XCTAssertEqual(try Data(contentsOf: storedURL), Data("local-pdf".utf8))
    }

    func testStoreManagedLocalPDFRenamesFileAlreadyInsideStorageDirectory() async throws {
        let storageDirectoryURL = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectoryURL) }

        let originalURL = storageDirectoryURL.appendingPathComponent("incoming-paper.pdf")
        try Data("local-pdf".utf8).write(to: originalURL)

        let paper = Paper(
            id: UUID(uuidString: "12345678-90AB-CDEF-1234-567890ABCDEF")!,
            title: "Agents & Tools",
            pdfURL: originalURL
        )
        let settings = UserSettings(
            paperStorageMode: .customLocal,
            customPaperStoragePath: storageDirectoryURL.path
        )
        let service = PaperStorageService(defaultStorageDirectoryURL: storageDirectoryURL)

        let location = try await service.storeManagedLocalPDF(from: originalURL, for: paper, settings: settings)

        guard case let .local(storedURL) = location else {
            return XCTFail("Expected a local managed storage location")
        }

        XCTAssertEqual(storedURL.lastPathComponent, "agents-tools-12345678.pdf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertEqual(try Data(contentsOf: storedURL), Data("local-pdf".utf8))
    }

    func testStoreManagedPDFUploadsToRemoteSSHWithExpectedCommands() async throws {
        let credentialStore = FakePaperStorageCredentialStore(
            storedPasswords: [
                PaperStorageRemoteEndpoint(host: "example.com", port: 2222, username: "reader"): "secret"
            ]
        )
        let commandRunner = RecordingCommandRunner()
        let pdfURL = URL(string: "https://example.com/remote-paper.pdf")!
        let paper = Paper(id: UUID(uuidString: "12345678-0000-0000-0000-000000000000")!, title: "Remote Paper", pdfURL: pdfURL)
        let settings = UserSettings(
            paperStorageMode: .remoteSSH,
            remotePaperStorageHost: "example.com",
            remotePaperStoragePort: 2222,
            remotePaperStorageUsername: "reader",
            remotePaperStorageDirectory: "/srv/papers"
        )
        let service = PaperStorageService(
            networking: StubNetworking { url in
                XCTAssertEqual(url, pdfURL)
                return (Data("remote-pdf".utf8), TestSupport.httpResponse(url: url))
            },
            credentialStore: credentialStore,
            commandRunner: commandRunner
        )

        let location = try await service.storeManagedPDF(for: paper, settings: settings)

        guard case let .remote(remoteURL) = location else {
            return XCTFail("Expected a remote managed storage location")
        }

        XCTAssertEqual(remoteURL.absoluteString, "sftp://reader@example.com:2222/srv/papers/remote-paper-12345678.pdf")
        XCTAssertEqual(commandRunner.invocations.count, 2)
        XCTAssertEqual(commandRunner.invocations[0].executableURL.path, "/usr/bin/ssh")
        XCTAssertTrue(commandRunner.invocations[0].arguments.contains("reader@example.com"))
        XCTAssertTrue(commandRunner.invocations[0].arguments.contains("mkdir -p -- '/srv/papers'"))
        XCTAssertEqual(commandRunner.invocations[1].executableURL.path, "/usr/bin/sftp")
        XCTAssertTrue(commandRunner.invocations[1].environment["SSH_ASKPASS"]?.isEmpty == false)
        let uploadCommand = try XCTUnwrap(
            String(data: XCTUnwrap(commandRunner.invocations[1].standardInput), encoding: .utf8)
        )
        XCTAssertTrue(
            uploadCommand.contains("put \"")
        )
        XCTAssertTrue(
            uploadCommand.contains("\"/srv/papers/remote-paper-12345678.pdf\"")
        )
    }

    func testMaterializeRemoteManagedPDFDownloadsIntoCacheDirectory() async throws {
        let cacheDirectoryURL = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectoryURL) }

        let commandRunner = RecordingCommandRunner()
        let credentialStore = FakePaperStorageCredentialStore(
            storedPasswords: [
                PaperStorageRemoteEndpoint(host: "example.com", port: 22, username: "reader"): "secret"
            ]
        )
        let paper = Paper(
            title: "Remote Paper",
            managedPDFRemoteURLString: "sftp://reader@example.com:22/papers/remote-paper.pdf"
        )
        let service = PaperStorageService(
            credentialStore: credentialStore,
            commandRunner: commandRunner
        )

        let localURL = try await service.materializeRemoteManagedPDF(for: paper, cacheDirectoryURL: cacheDirectoryURL)

        XCTAssertEqual(localURL.path, cacheDirectoryURL.appendingPathComponent("remote-paper.pdf").path)
        XCTAssertEqual(commandRunner.invocations.count, 1)
        XCTAssertEqual(commandRunner.invocations[0].executableURL.path, "/usr/bin/sftp")
        let downloadCommand = try XCTUnwrap(
            String(data: XCTUnwrap(commandRunner.invocations[0].standardInput), encoding: .utf8)
        )
        XCTAssertTrue(
            downloadCommand.contains("get \"/papers/remote-paper.pdf\" \"\(localURL.path)\"")
        )
    }

    func testKeychainPaperStorageCredentialStoreSavesLoadsAndDeletesPassword() throws {
        let store = KeychainPaperStorageCredentialStore(service: "PaperMasterTests.\(UUID().uuidString)")
        let endpoint = PaperStorageRemoteEndpoint(host: "example.com", port: 22, username: "reader")
        defer { try? store.deletePassword(for: endpoint) }

        XCTAssertNil(try store.loadPassword(for: endpoint))

        try store.savePassword("secret", for: endpoint)
        XCTAssertEqual(try store.loadPassword(for: endpoint), "secret")

        try store.deletePassword(for: endpoint)
        XCTAssertNil(try store.loadPassword(for: endpoint))
    }
}
