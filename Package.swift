// swift-tools-version: 6.2
import PackageDescription
import Foundation

// Application tests link the updater through ThreadApp; this path is test-only.
let testFrameworks = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent(".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64").path

let package = Package(
    name: "Thread",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Thread", targets: ["ThreadApp"]),
               .executable(name: "ThreadShellSend", targets: ["ThreadShellSend"]),
               .executable(name: "ThreadBrowserHost", targets: ["ThreadBrowserHost"]),
               .executable(name: "ThreadAgent", targets: ["ThreadAgent"])],
    dependencies: [
        .package(path: "Packages/ThreadDomain"),
        .package(path: "Packages/ThreadEngine"),
        .package(path: "Packages/ThreadPersistence"),
        .package(path: "Packages/ThreadMacOS"),
        .package(path: "Packages/ThreadBrowser"),
        .package(path: "Packages/ThreadShell"),
        .package(path: "Packages/ThreadGit"),
        .package(path: "Packages/ThreadDecisions"),
        .package(path: "Packages/ThreadRestore"),
        .package(path: "Packages/ThreadUI"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "ThreadActivity", dependencies: ["ThreadDomain", "ThreadEngine", "ThreadPersistence", "ThreadMacOS", "ThreadShell", "ThreadGit", "ThreadBrowser", "ThreadDecisions", "ThreadRestore"], path: "Sources/ThreadActivity"),
        .target(name: "ThreadAgentTransport", dependencies: ["ThreadDomain"], path: "Sources/ThreadAgentTransport"),
        .executableTarget(name: "ThreadAgent", dependencies: ["ThreadAgentTransport", "ThreadActivity", "ThreadDomain"], path: "ThreadAgent", exclude: ["Resources"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "ThreadAgentRuntimeTests", dependencies: ["ThreadAgent", "ThreadAgentTransport"], path: "Tests/AgentRuntime"),
        .testTarget(name: "ThreadAgentTransportTests", dependencies: ["ThreadAgentTransport"], path: "Tests/AgentTransport"),
        .testTarget(name: "ThreadPipelineTests", dependencies: ["ThreadDomain", "ThreadEngine", "ThreadDecisions", "ThreadPersistence"], path: "Tests", exclude: ["Application", "AgentTransport", "AgentRuntime"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ThreadApplicationTests", dependencies: ["ThreadApp", "ThreadActivity", "ThreadAgentTransport", "ThreadDomain", "ThreadMacOS", "ThreadDecisions", "ThreadPersistence", "ThreadUI"], path: "Tests/Application",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", testFrameworks])]),
        .target(name: "ThreadSafariNative", dependencies: ["ThreadBrowser"], path: "BrowserExtensions/Safari/Native"),
        .executableTarget(name: "ThreadBrowserHost", dependencies: ["ThreadBrowser", "ThreadMacOS", "ThreadDomain"], path: "BrowserExtensions/NativeHost"),
        .executableTarget(name: "ThreadShellSend", dependencies: ["ThreadShell"], path: "ShellIntegration/Bridge"),
        .executableTarget(
            name: "ThreadApp",
            dependencies: [
                "ThreadAgentTransport", "ThreadDomain", "ThreadPersistence", "ThreadMacOS", "ThreadUI",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "ThreadApp",
            exclude: ["Resources"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
