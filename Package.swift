// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hugora",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Hugora", targets: ["Hugora"]),
        .executable(name: "hugora-cli", targets: ["hugora-cli"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "Hugora",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/Hugora",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "HugoraTests",
            dependencies: ["Hugora"],
            path: "Tests/HugoraTests"
        ),
        .executableTarget(
            name: "hugora-cli",
            path: "Sources/hugora-cli"
        )
    ]
)
