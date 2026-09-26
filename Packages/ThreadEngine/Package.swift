// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreadEngine",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ThreadEngine", targets: ["ThreadEngine"])],
    dependencies: [.package(path: "../ThreadDomain")],
    targets: [
        .target(name: "ThreadEngine", dependencies: ["ThreadDomain"]),
        .testTarget(name: "ThreadEngineTests", dependencies: ["ThreadEngine", "ThreadDomain"])
    ]
)
