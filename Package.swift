// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScrollWM",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ScrollWM",
            path: "Sources/ScrollWM",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ScrollWMTests",
            dependencies: ["ScrollWM"],
            path: "Tests/ScrollWMTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
