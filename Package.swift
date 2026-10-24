// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LocalAI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LocalAI", targets: ["LocalAI"])
    ],
    targets: [
        .executableTarget(
            name: "LocalAI",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "LocalAITests",
            dependencies: [
                .target(name: "LocalAI")
            ]
        )
    ]
)

