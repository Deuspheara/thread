// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreadGit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ThreadGit", targets: ["ThreadGit"])],
    dependencies: [.package(path: "../ThreadDomain")],
    targets: [
        .target(name: "ThreadGit", dependencies: ["ThreadDomain"]),
        .testTarget(name: "ThreadGitTests", dependencies: ["ThreadGit", "ThreadDomain"])
    ]
)
