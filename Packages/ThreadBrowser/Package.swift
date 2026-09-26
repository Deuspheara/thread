// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ThreadBrowser",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ThreadBrowser", targets: ["ThreadBrowser"])],
    dependencies: [.package(path: "../ThreadDomain")],
    targets: [
        .target(name: "ThreadBrowser", dependencies: ["ThreadDomain"]),
        .testTarget(name: "ThreadBrowserTests", dependencies: ["ThreadBrowser", "ThreadDomain"])
    ]
)