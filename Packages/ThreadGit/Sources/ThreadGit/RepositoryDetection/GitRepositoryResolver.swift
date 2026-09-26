import Foundation
import ThreadDomain

/// Resolves local worktree metadata on demand with a bounded, short-lived cwd cache.
public actor GitRepositoryResolver {
    private struct Entry { let resolution: RepositoryResolution; let date: Date }
    private var cache: [String: Entry] = [:]
    private let runner: any GitCommandRunning
    private let now: @Sendable () -> Date
    private let lifetime: TimeInterval

    public init() {
        runner = GitCommandRunner()
        now = Date.init
        lifetime = 2
    }

    init(runner: any GitCommandRunning, now: @escaping @Sendable () -> Date, lifetime: TimeInterval = 2) {
        self.runner = runner
        self.now = now
        self.lifetime = lifetime
    }

    public func resolve(directory: String, refresh: Bool = false) async throws -> RepositoryResolution {
        guard directory.hasPrefix("/"), !directory.utf8.contains(0), directory.utf8.count <= 4096 else {
            throw GitReadError.malformedOutput
        }
        let key = URL(fileURLWithPath: directory).standardizedFileURL.resolvingSymlinksInPath().path
        if !refresh, let entry = cache[key], now().timeIntervalSince(entry.date) < lifetime { return entry.resolution }
        let resolution = try await read(directory: key)
        try Task.checkCancellation()
        if cache.count >= 128, let oldest = cache.min(by: { $0.value.date < $1.value.date })?.key { cache.removeValue(forKey: oldest) }
        cache[key] = Entry(resolution: resolution, date: now())
        return resolution
    }

    private func read(directory: String) async throws -> RepositoryResolution {
        let rootResult = try await runner.run(directory: directory, arguments: ["rev-parse", "--show-toplevel"])
        guard rootResult.status == 0 else {
            // Only classify an existing readable directory as non-repository; disappearance is an integration failure.
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue,
                  FileManager.default.isReadableFile(atPath: directory) else { throw GitReadError.unavailable }
            var parent = URL(fileURLWithPath: directory)
            while true {
                if FileManager.default.fileExists(atPath: parent.appendingPathComponent(".git").path) {
                    throw GitReadError.unavailable
                }
                let next = parent.deletingLastPathComponent()
                if next == parent { break }
                parent = next
            }
            return .notRepository
        }
        let root = try path(from: rootResult)
        let common = try await runner.run(directory: directory, arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"])
        let gitDirectory = try await runner.run(directory: directory, arguments: ["rev-parse", "--absolute-git-dir"])
        let filters = try await runner.run(directory: directory, arguments: ["config", "--null", "--name-only", "--get-regexp", "^filter\\..*\\.(clean|smudge|process|required)$"])
        let overrides = try GitFilterPolicy.overrides(from: filters)
        let status = try await runner.run(directory: directory, arguments: overrides + ["status", "--porcelain=v2", "-z", "--branch",
                                                                          "--untracked-files=no", "--ignore-submodules=all", "--no-renames"])
        guard status.status == 0 else { throw GitReadError.unavailable }
        let snapshot = try GitStatusSnapshot(data: status.output)
        let dirty = RepositoryDirtySummary(changedTrackedFiles: snapshot.dirty.changedTrackedFiles,
                                           conflictedFiles: snapshot.dirty.conflictedFiles, isApproximate: !overrides.isEmpty)
        return .available(RepositoryContext(identity: RepositoryIdentity(commonDirectory: try path(from: common)),
                                            rootPath: root, gitDirectory: try path(from: gitDirectory), branch: snapshot.branch,
                                            head: snapshot.head, dirty: dirty))
    }

    private func path(from result: GitCommandResult) throws -> String {
        guard result.status == 0, var path = String(data: result.output, encoding: .utf8), path.hasSuffix("\n") else {
            throw GitReadError.malformedOutput
        }
        path.removeLast() // Preserve embedded newlines and trailing spaces in valid paths.
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { throw GitReadError.malformedOutput }
        return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
