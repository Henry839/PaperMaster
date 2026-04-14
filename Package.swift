// swift-tools-version: 5.9

import PackageDescription
import Foundation

let environment = ProcessInfo.processInfo.environment
let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
let useLegacyMode = operatingSystemVersion.majorVersion < 14
let useCompatibilityApp = environment["PAPERMASTER_FORCE_COMPATIBILITY_APP"] == "1"
let compatibilitySources = [
    "PaperMaster.swift",
    "Compatibility/LegacyPaperMasterApp.swift"
]
let paperMasterSwiftSettings: [SwiftSetting] = {
    var settings: [SwiftSetting] = []

    if useLegacyMode {
        settings.append(.define("PAPERMASTER_LEGACY_MODE"))
    }

    if useCompatibilityApp {
        settings.append(.define("PAPERMASTER_COMPATIBILITY_APP"))
    }

    return settings
}()

let compatibilityExcludes: [String] = {
    guard useCompatibilityApp else { return [] }

    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .appendingPathComponent("Sources/PaperMaster", isDirectory: true)

    guard let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    let included = Set(compatibilitySources)
    var excluded: [String] = []

    for case let fileURL as URL in enumerator {
        guard fileURL.pathExtension == "swift" else { continue }
        let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        guard included.contains(relativePath) == false else { continue }
        excluded.append(relativePath)
    }

    return excluded.sorted()
}()

let paperMasterTarget: Target = .executableTarget(
    name: "PaperMaster",
    dependencies: [
        "SwiftTerm"
    ],
    path: "Sources/PaperMaster",
    exclude: compatibilityExcludes,
    sources: useCompatibilityApp ? compatibilitySources : nil,
    swiftSettings: paperMasterSwiftSettings
)

let packageTargets: [Target] = {
    if useCompatibilityApp {
        return [paperMasterTarget]
    }

    return [
        paperMasterTarget,
        .testTarget(
            name: "PaperMasterTests",
            dependencies: ["PaperMaster"],
            path: "Tests/PaperMasterTests"
        )
    ]
}()

let package = Package(
    name: "PaperMaster",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "PaperMaster",
            targets: ["PaperMaster"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", branch: "main")
    ],
    targets: packageTargets
)
