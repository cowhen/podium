// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Podium",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Podium",
            path: "Sources/Podium",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PodiumTests",
            dependencies: ["Podium"],
            path: "Tests/PodiumTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
