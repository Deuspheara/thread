// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreadDecisions",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ThreadDecisions", targets: ["ThreadDecisions"])],
    dependencies: [.package(path: "../ThreadDomain")],
    targets: [
        .target(name: "ThreadDecisions", dependencies: ["ThreadDomain"]),
        .testTarget(name: "ThreadDecisionsTests", dependencies: ["ThreadDecisions", "ThreadDomain"])
    ]
)
