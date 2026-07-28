// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HiggsfieldUsageCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HiggsfieldUsageCore", path: "Sources/HiggsfieldUsageCore"),
        .testTarget(
            name: "HiggsfieldUsageCoreTests",
            dependencies: ["HiggsfieldUsageCore"],
            path: "Tests/HiggsfieldUsageCoreTests"
        ),
    ]
)
