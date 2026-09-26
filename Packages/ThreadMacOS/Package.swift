// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ThreadMacOS",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ThreadMacOS", targets: ["ThreadMacOS"])],
    dependencies: [.package(path: "../ThreadDomain")],
    targets: [
        .target(name: "ThreadMacOS", dependencies: ["ThreadDomain"]),
        .testTarget(name: "ThreadMacOSTests", dependencies: ["ThreadMacOS", "ThreadDomain"])
    ]
)
