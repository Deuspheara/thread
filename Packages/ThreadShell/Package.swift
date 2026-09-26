// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ThreadShell",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ThreadShell", targets: ["ThreadShell"])],
    dependencies: [.package(path: "../ThreadDomain")],
    targets: [
        .target(name: "ThreadShell", dependencies: ["ThreadDomain"]),
        .testTarget(name: "ThreadShellTests", dependencies: ["ThreadShell", "ThreadDomain"])
    ]
)
