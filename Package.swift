// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PaperMaster",
    platforms: [
        .macOS(.v14)
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
    targets: [
        .executableTarget(
            name: "PaperMaster",
            dependencies: [
                "SwiftTerm"
            ],
            path: "Sources/PaperMaster"
        ),
        .testTarget(
            name: "PaperMasterTests",
            dependencies: ["PaperMaster"],
            path: "Tests/PaperMasterTests"
        )
    ]
)
