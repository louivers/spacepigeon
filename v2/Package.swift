// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SpacePigeonV2",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "SpacePigeonCore", targets: ["SpacePigeonCore"]),
        .executable(name: "spacepigeon", targets: ["SpacePigeonCLI"]),
        .executable(name: "spacepigeond", targets: ["SpacePigeonDaemon"]),
    ],
    targets: [
        .target(
            name: "SpacePigeonCore",
            path: "daemon/Sources/SpacePigeonCore"
        ),
        .executableTarget(
            name: "SpacePigeonCLI",
            dependencies: ["SpacePigeonCore"],
            path: "cli/Sources/SpacePigeonCLI"
        ),
        .executableTarget(
            name: "SpacePigeonDaemon",
            dependencies: ["SpacePigeonCore"],
            path: "daemon/Sources/SpacePigeonDaemon"
        ),
    ]
)
