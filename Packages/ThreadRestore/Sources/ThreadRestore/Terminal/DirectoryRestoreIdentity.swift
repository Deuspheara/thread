import Foundation

/// Resolves local directory aliases for one restore plan without changing stored resource metadata.
public struct DirectoryRestoreIdentity: Sendable {
    public init() {}

    public func canonicalPath(_ path: String) -> String {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return path }
        return URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
