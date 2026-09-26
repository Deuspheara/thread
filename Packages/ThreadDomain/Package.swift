// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreadDomain",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ThreadDomain", targets: ["ThreadDomain"])],
    dependencies: [],
    targets: [
        .target(name: "ThreadDomain", dependencies: [])
    ]
)
