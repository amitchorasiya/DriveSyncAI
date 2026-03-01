// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DriveSyncAI",
    platforms: [.macOS(.v14)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DriveSyncAI",
            path: "Sources/DriveSyncAI",
            resources: [.process("Resources")]
        )
    ]
)
