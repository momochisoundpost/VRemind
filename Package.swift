// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CaitlynSwift",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "CaitlynKit", targets: ["CaitlynKit"]),
        .executable(name: "CaitlynSwift", targets: ["CaitlynSwift"]),
    ],
    targets: [
        .target(
            name: "CaitlynKit",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "CaitlynSwift",
            dependencies: ["CaitlynKit"]
        ),
        .testTarget(
            name: "CaitlynKitTests",
            dependencies: ["CaitlynKit"]
        ),
    ]
)
