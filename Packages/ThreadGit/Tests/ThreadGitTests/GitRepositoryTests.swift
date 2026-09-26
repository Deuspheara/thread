import Foundation
import Testing
import ThreadDomain
@testable import ThreadGit

struct GitRepositoryTests {
    @Test func resolvesUnbornBranchCommitDirtyStateAndDetachedHEAD() async throws {
        let repo = try TemporaryRepository()
        defer { repo.remove() }
        let resolver = GitRepositoryResolver()
        let unborn = try available(await resolver.resolve(directory: repo.path))
        #expect(unborn.branch == "main")
        #expect(unborn.head == nil)
        try repo.commit()
        let committed = try available(await resolver.resolve(directory: repo.path, refresh: true))
        #expect(committed.head?.count == 40)
        #expect(committed.dirty.changedTrackedFiles == 0)
        try Data("changed".utf8).write(to: repo.url.appendingPathComponent("file.txt"))
        let dirty = try available(await resolver.resolve(directory: repo.path, refresh: true))
        #expect(dirty.dirty.changedTrackedFiles == 1)
        try repo.git(["checkout", "--detach"])
        let detached = try available(await resolver.resolve(directory: repo.path, refresh: true))
        #expect(detached.branch == nil)
        #expect(detached.head == committed.head)
    }

    @Test func linkedWorktreesShareCloneIdentityButKeepSeparateRootsAndBranches() async throws {
        let repo = try TemporaryRepository()
        defer { repo.remove() }
        try repo.commit()
        let linked = repo.url.appendingPathComponent("linked")
        try repo.git(["worktree", "add", "-b", "feature/test", linked.path])
        let resolver = GitRepositoryResolver()
        let main = try available(await resolver.resolve(directory: repo.path))
        let worktree = try available(await resolver.resolve(directory: linked.path))
        #expect(main.identity == worktree.identity)
        #expect(main.gitDirectory != worktree.gitDirectory)
        #expect(worktree.rootPath == linked.standardizedFileURL.resolvingSymlinksInPath().path)
        #expect(worktree.branch == "feature/test")
    }

    @Test func pathWithSpacesNewlinesAndShellSyntaxIsNeverEvaluated() async throws {
        let repo = try TemporaryRepository(suffix: " 'quote' $(false)\nproject")
        defer { repo.remove() }
        let resolver = GitRepositoryResolver()
        let result = try available(await resolver.resolve(directory: repo.path))
        #expect(result.rootPath == repo.url.standardizedFileURL.resolvingSymlinksInPath().path)
        #expect(result.branch == "main")
    }

    @Test func distinguishesNonRepositoryFromMissingDirectory() async throws {
        let directory = URL(fileURLWithPath: "/private/tmp/tgit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let resolver = GitRepositoryResolver()
        #expect(try await resolver.resolve(directory: directory.path) == .notRepository)
        await #expect(throws: (any Error).self) { try await resolver.resolve(directory: directory.appendingPathComponent("missing").path) }
    }

    private func available(_ result: RepositoryResolution) throws -> RepositoryContext {
        guard case .available(let context) = result else { throw GitReadError.malformedOutput }
        return context
    }
}

struct TemporaryRepository {
    let url: URL
    var path: String { url.path }

    init(suffix: String = "") throws {
        url = URL(fileURLWithPath: "/private/tmp/tgit-" + UUID().uuidString + suffix)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        try git(["init", "-b", "main"])
    }

    func commit() throws {
        try Data("initial".utf8).write(to: url.appendingPathComponent("file.txt"))
        try git(["add", "file.txt"])
        try git(["-c", "user.name=Thread Test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false", "commit", "-m", "fixture"])
    }

    func git(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path] + arguments
        process.environment = ["PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw GitReadError.unavailable }
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}
