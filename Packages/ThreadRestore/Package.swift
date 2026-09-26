// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreadRestore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ThreadRestore", targets: ["ThreadRestore"])],
    dependencies: [.package(path: "../ThreadDomain")],
    targets: [
        .target(name: "ThreadRestore", dependencies: ["ThreadDomain"]),
        .testTarget(name: "ThreadRestoreTests", dependencies: ["ThreadRestore", "ThreadDomain"])
    ]
)
