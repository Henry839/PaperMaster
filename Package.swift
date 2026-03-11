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
    targets: [
        .executableTarget(
            name: "PaperMaster",
            path: "Sources/PaperMaster"
        ),
        .testTarget(
            name: "PaperMasterTests",
            dependencies: ["PaperMaster"],
            path: "Tests/PaperMasterTests"
        )
    ]
)
