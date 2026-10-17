// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InkLift",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "InkCore", targets: ["InkCore"]),
        .executable(name: "inklift", targets: ["inklift"]),
        .executable(name: "InkLiftMac", targets: ["InkLiftMac"]),
    ],
    targets: [
        .target(name: "InkCore", resources: [.copy("Resources/goodnotes-template")]),
        .executableTarget(name: "inklift", dependencies: ["InkCore"]),
        .executableTarget(name: "InkLiftMac", dependencies: ["InkCore"]),
        .testTarget(name: "InkCoreTests", dependencies: ["InkCore"]),
    ]
)
