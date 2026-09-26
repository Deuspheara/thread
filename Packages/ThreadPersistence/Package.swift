// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreadPersistence",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ThreadPersistence", targets: ["ThreadPersistence"])],
    dependencies: [.package(path: "../ThreadDomain"), .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")],
    targets: [
        .target(name: "ThreadPersistence", dependencies: ["ThreadDomain", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "ThreadPersistenceTests", dependencies: ["ThreadPersistence", "ThreadDomain", .product(name: "GRDB", package: "GRDB.swift")])
    ]
)
