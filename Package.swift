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
    dependencies: [
        .package(url: "https://github.com/momochisoundpost/VRemindCore.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "VRemindKit",
            dependencies: [
                .product(name: "VRemindCore", package: "VRemindCore"),
            ]
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
