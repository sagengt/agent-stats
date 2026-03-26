// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentStats",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "AgentStats",
            path: "AgentStats",
            exclude: ["App/AgentStatsApp.swift"],  // @main excluded for library target
            swiftSettings: [.define("TESTING")]
        ),
        .testTarget(
            name: "AgentStatsTests",
            dependencies: ["AgentStats"],
            path: "AgentStatsTests"
        ),
    ]
)
