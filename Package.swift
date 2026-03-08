// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PaperReadingScheduler",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "PaperReadingScheduler",
            targets: ["PaperReadingScheduler"]
        )
    ],
    targets: [
        .executableTarget(
            name: "PaperReadingScheduler",
            path: "Sources/PaperReadingScheduler"
        ),
        .testTarget(
            name: "PaperReadingSchedulerTests",
            dependencies: ["PaperReadingScheduler"],
            path: "Tests/PaperReadingSchedulerTests"
        )
    ]
)
