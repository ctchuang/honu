// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Honu",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Honu",
            resources: [.copy("Resources/icon.png"), .copy("BuiltinApps")]
        ),
        .testTarget(
            name: "HonuTests",
            dependencies: ["Honu"]
        ),
    ]
)
