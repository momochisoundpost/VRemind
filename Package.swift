// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VRemind",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "VRemindCore", targets: ["VRemindCore"]),
        .library(name: "VRemindKit", targets: ["VRemindKit"]),
        .executable(name: "VRemind", targets: ["VRemind"]),
        .executable(name: "VRemindWidget", targets: ["VRemindWidget"]),
    ],
    targets: [
        .target(
            name: "VRemindCore",
            exclude: ["README.md"]
        ),
        .target(
            name: "VRemindKit",
            dependencies: ["VRemindCore"]
        ),
        .executableTarget(
            name: "VRemind",
            dependencies: ["VRemindKit"]
        ),
        .executableTarget(
            name: "VRemindWidget",
            dependencies: ["VRemindKit"],
            path: "Sources/VRemindWidget",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])
            ]
        ),
        .testTarget(
            name: "VRemindCoreTests",
            dependencies: ["VRemindCore"]
        ),
        .testTarget(
            name: "VRemindKitTests",
            dependencies: ["VRemindKit"]
        ),
    ]
)
