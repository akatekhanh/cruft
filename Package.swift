// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cruft",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CruftCore"),
        .target(name: "CruftInfra", dependencies: ["CruftCore"]),
        .executableTarget(name: "CruftApp", dependencies: ["CruftCore", "CruftInfra"]),
        .executableTarget(name: "CruftChecks", dependencies: ["CruftCore", "CruftInfra"]),
        .testTarget(name: "CruftCoreTests", dependencies: ["CruftCore"]),
        .testTarget(name: "CruftInfraTests", dependencies: ["CruftCore", "CruftInfra"]),
    ]
)
