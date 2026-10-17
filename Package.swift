// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InkLift",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "InkCore", targets: ["InkCore"]),
        .executable(name: "inklift", targets: ["inklift"]),
    ],
    targets: [
        .target(name: "InkCore"),
        .executableTarget(name: "inklift", dependencies: ["InkCore"]),
        .testTarget(name: "InkCoreTests", dependencies: ["InkCore"]),
    ]
)
