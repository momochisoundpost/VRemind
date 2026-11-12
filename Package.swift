// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VRemind",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "VRemindKit", targets: ["VRemindKit"]),
        .executable(name: "VRemind", targets: ["VRemind"]),
        .executable(name: "VRemindWidget", targets: ["VRemindWidget"]),
    ],
    targets: [
        .target(
            name: "VRemindKit"
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
            name: "VRemindKitTests",
            dependencies: ["VRemindKit"]
        ),
    ]
)
