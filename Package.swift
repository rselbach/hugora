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
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.1"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Hugora",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "TOMLKit", package: "TOMLKit"),
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
