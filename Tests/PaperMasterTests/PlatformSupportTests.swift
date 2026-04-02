import Foundation
import SwiftData
import XCTest
@testable import PaperMasterShared

@MainActor
final class PlatformSupportTests: XCTestCase {
    func testSupportedStorageModesExcludeRemoteWhenCapabilityDisabled() {
        let capabilities = PlatformCapabilities(
            supportsIntegratedTerminal: false,
            supportsRemotePaperStorage: false,
            supportsSeparateReaderWindow: false
        )

        XCTAssertEqual(
            PaperStorageMode.supportedCases(capabilities: capabilities),
            [.defaultLocal, .customLocal]
        )
    }

    func testPaperStorageReadinessReportsConfiguredCustomFolder() throws {
        let customFolderURL = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: customFolderURL) }

        let settings = UserSettings(
            paperStorageMode: .customLocal,
            customPaperStoragePath: customFolderURL.path
        )
        #if os(iOS)
        settings.customPaperStorageBookmarkData = try SecurityScopedURLAccess.bookmarkData(for: customFolderURL)
        #endif

        XCTAssertEqual(
            settings.paperStorageReadiness(
                defaultDirectoryURL: customFolderURL,
                hasRemotePassword: false,
                capabilities: PlatformCapabilities(
                    supportsIntegratedTerminal: false,
                    supportsRemotePaperStorage: false,
                    supportsSeparateReaderWindow: false
                )
            ),
            .readyCustomLocal(path: customFolderURL.path)
        )
    }

    func testNormalizeSettingsForPlatformFallsBackFromRemoteSSH() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(paperStorageMode: .remoteSSH)
        context.insert(settings)

        makeServices(
            capabilities: PlatformCapabilities(
                supportsIntegratedTerminal: false,
                supportsRemotePaperStorage: false,
                supportsSeparateReaderWindow: false
            )
        ).normalizeSettingsForPlatform(settings, context: context)

        XCTAssertEqual(settings.paperStorageMode, .defaultLocal)
    }

    func testSetCustomPaperStorageFolderStoresBookmarkAndDisplayName() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = UserSettings(paperStorageMode: .customLocal)
        context.insert(settings)

        let customFolderURL = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: customFolderURL) }

        makeServices().setCustomPaperStorageFolder(customFolderURL, for: settings, context: context)

        XCTAssertEqual(settings.customPaperStoragePath, customFolderURL.path)
        XCTAssertEqual(settings.customPaperStorageFolderDisplayName, customFolderURL.lastPathComponent)
        XCTAssertNotNil(settings.customPaperStorageBookmarkData)
    }

    private func makeServices(capabilities: PlatformCapabilities = .current) -> AppServices {
        AppServices(
            importService: PaperImportService(
                metadataResolver: StubMetadataResolver(
                    metadata: ResolvedPaperMetadata(
                        title: "",
                        authors: [],
                        abstractText: "",
                        sourceURL: nil,
                        pdfURL: nil
                    )
                )
            ),
            reminderService: ReminderService(center: FakeNotificationCenter()),
            platformCapabilities: capabilities
        )
    }
}
