// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MDViewer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MDViewer",
            path: "Sources/MDViewer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
