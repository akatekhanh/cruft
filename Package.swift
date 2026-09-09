// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sweep",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SweepCore"),
        .target(name: "SweepInfra", dependencies: ["SweepCore"]),
        .executableTarget(name: "SweepApp", dependencies: ["SweepCore", "SweepInfra"]),
        .executableTarget(name: "SweepChecks", dependencies: ["SweepCore", "SweepInfra"]),
        .testTarget(name: "SweepCoreTests", dependencies: ["SweepCore"]),
        .testTarget(name: "SweepInfraTests", dependencies: ["SweepCore", "SweepInfra"]),
    ]
)
