import Foundation

/// Identifies a local clone by its canonical common Git directory, shared by linked worktrees.
public struct RepositoryIdentity: Hashable, Codable, Sendable {
    public let commonDirectory: String
    public init(commonDirectory: String) { self.commonDirectory = commonDirectory }
}

/// Summarizes tracked changes without retaining filenames or file contents.
public struct RepositoryDirtySummary: Equatable, Codable, Sendable {
    public let changedTrackedFiles: Int
    public let conflictedFiles: Int
    public let isApproximate: Bool
    public init(changedTrackedFiles: Int, conflictedFiles: Int, isApproximate: Bool = false) {
        self.changedTrackedFiles = changedTrackedFiles
        self.conflictedFiles = conflictedFiles
        self.isApproximate = isApproximate
    }
}

/// Captures a clone's current worktree, branch (nil when detached), and optional unborn HEAD.
public struct RepositoryContext: Equatable, Codable, Sendable {
    public let identity: RepositoryIdentity
    public let rootPath: String
    public let gitDirectory: String
    public let branch: String?
    public let head: String?
    public let dirty: RepositoryDirtySummary

    public init(identity: RepositoryIdentity, rootPath: String, gitDirectory: String, branch: String?,
                head: String?, dirty: RepositoryDirtySummary) {
        self.identity = identity
        self.rootPath = rootPath
        self.gitDirectory = gitDirectory
        self.branch = branch
        self.head = head
        self.dirty = dirty
    }
}

public enum RepositoryResolution: Equatable, Codable, Sendable {
    case available(RepositoryContext)
    case notRepository
    case unavailable
}

/// Associates asynchronous Git evidence with the exact shell observation that requested it.
public struct RepositoryObservation: Equatable, Codable, Sendable {
    public let terminal: TerminalSessionIdentity
    public let sequence: UInt64
    public let resolution: RepositoryResolution
    public init(terminal: TerminalSessionIdentity, sequence: UInt64, resolution: RepositoryResolution) {
        self.terminal = terminal
        self.sequence = sequence
        self.resolution = resolution
    }
}
