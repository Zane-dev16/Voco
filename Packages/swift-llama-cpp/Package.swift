// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "swift-llama-cpp",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "SwiftLlama",
            targets: ["SwiftLlama"]),
    ],
    targets: [
        .target(
            name: "SwiftLlama",
            dependencies: ["llama"]
        ),
        .binaryTarget(
            name: "llama",
            path: "llama.xcframework"
        ),
        .testTarget(
            name: "SwiftLlamaTests",
            dependencies: ["SwiftLlama"],
            resources: [.copy("Resources")]
        ),
    ]
)
