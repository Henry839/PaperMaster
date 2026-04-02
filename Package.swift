// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PaperMaster",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "PaperMasterShared",
            targets: ["PaperMasterShared"]
        ),
        .executable(
            name: "PaperMaster",
            targets: ["PaperMaster"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/migueldeicaza/SwiftTerm.git",
            revision: "3c45fdcfcf4395c72d2a4ee23c0bce79017b5391"
        )
    ],
    targets: [
        .target(
            name: "PaperMasterShared",
            dependencies: [
                .product(
                    name: "SwiftTerm",
                    package: "SwiftTerm",
                    condition: .when(platforms: [.macOS])
                )
            ],
            path: "Sources/PaperMaster"
        ),
        .executableTarget(
            name: "PaperMaster",
            dependencies: [
                "PaperMasterShared"
            ],
            path: "Sources/PaperMasterMac"
        ),
        .testTarget(
            name: "PaperMasterTests",
            dependencies: ["PaperMasterShared"],
            path: "Tests/PaperMasterTests"
        )
    ]
)
