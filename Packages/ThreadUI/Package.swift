// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreadUI",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ThreadUI", targets: ["ThreadUI"])],
    dependencies: [.package(path: "../ThreadDomain")],
    targets: [
        .target(name: "ThreadUI", dependencies: ["ThreadDomain"]),
        .testTarget(name: "ThreadUITests", dependencies: ["ThreadUI", "ThreadDomain"])
    ]
)
