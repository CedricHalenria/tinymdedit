// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TinyMDEdit",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TinyMDEdit",
            path: "Sources/TinyMDEdit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
