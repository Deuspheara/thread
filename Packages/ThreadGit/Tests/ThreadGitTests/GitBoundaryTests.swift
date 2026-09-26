import Foundation
import Testing
import ThreadDomain
@testable import ThreadGit

struct GitBoundaryTests {
    @Test func statusDoesNotExecuteRepositoryCleanFilter() async throws {
        let repo = try TemporaryRepository()
        defer { repo.remove() }
        try repo.commit()
        try repo.git(["config", "filter.probe.clean", "touch filter-ran; cat"])
        try repo.git(["config", "filter.probe.required", "true"])
        try Data("*.txt filter=probe\n".utf8).write(to: repo.url.appendingPathComponent(".gitattributes"))
        try Data("changed more".utf8).write(to: repo.url.appendingPathComponent("file.txt"))
        let result = try await GitRepositoryResolver().resolve(directory: repo.path)
        guard case .available(let context) = result else { Issue.record("Expected readable repository"); return }
        #expect(context.dirty.changedTrackedFiles == 1)
        #expect(context.dirty.isApproximate)
        #expect(!FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("filter-ran").path))
    }

    @Test func outputIsBoundedAndTimeoutTerminatesProcess() async throws {
        let repo = try TemporaryRepository()
        defer { repo.remove() }
        let bounded = GitCommandRunner(outputLimit: 2)
        await #expect(throws: (any Error).self) {
            try await bounded.run(directory: repo.path, arguments: ["rev-parse", "--show-toplevel"])
        }
        let deadline = GitCommandRunner(timeout: .nanoseconds(1))
        await #expect(throws: (any Error).self) {
            try await deadline.run(directory: repo.path, arguments: ["status", "--porcelain=v2"])
        }
    }

    @Test func repositoryCacheAvoidsRepeatedProcessesAndRefreshesOnCompletion() async throws {
        let runner = CountingGitRunner()
        let resolver = GitRepositoryResolver(runner: runner, now: { Date(timeIntervalSince1970: 1) })
        _ = try await resolver.resolve(directory: "/private/tmp")
        let initial = await runner.count
        _ = try await resolver.resolve(directory: "/private/tmp")
        #expect(await runner.count == initial)
        _ = try await resolver.resolve(directory: "/private/tmp", refresh: true)
        #expect(await runner.count == initial * 2)
    }
}

private actor CountingGitRunner: GitCommandRunning {
    var count = 0
    func run(directory: String, arguments: [String]) async throws -> GitCommandResult {
        count += 1
        let output: String
        if arguments.contains("status") { output = "# branch.oid (initial)\0# branch.head main\0" }
        else if arguments.contains("config") { return GitCommandResult(status: 1, output: Data()) }
        else { output = "/private/tmp/example\n" }
        return GitCommandResult(status: 0, output: Data(output.utf8))
    }
}
