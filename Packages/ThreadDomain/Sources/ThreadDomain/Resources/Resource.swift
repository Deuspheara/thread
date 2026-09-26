import Foundation

public struct FileIdentity: Hashable, Codable, Sendable {
    public let path: String
    public init(path: String) { self.path = path }
}

/// Uses typed natural identities; session-bound resources remain distinct from durable resources.
public enum ResourceID: Hashable, Codable, Sendable {
    case application(ApplicationIdentity)
    case window(WindowIdentity)
    case browserPage(BrowserKind, String)
    case terminal(TerminalSessionIdentity)
    case workingDirectory(String)
    case repository(RepositoryIdentity)
    case branch(RepositoryIdentity, String)
    case file(FileIdentity)
}

public enum ResourceKind: String, Codable, Sendable {
    case application, window, browserPage, terminal, workingDirectory, repository, branch, file
}

/// Holds typed metadata needed for matching and later capability-based restoration.
public enum Resource: Equatable, Codable, Sendable {
    case application(ApplicationContext)
    case window(WindowContext)
    case browserPage(BrowserTabContext)
    case terminal(TerminalContext)
    case workingDirectory(String)
    case repository(RepositoryContext)
    case branch(RepositoryIdentity, String)
    case file(FileIdentity)

    public var id: ResourceID {
        switch self {
        case .application(let value): .application(value.identity)
        case .window(let value): .window(value.identity)
        case .browserPage(let value): .browserPage(value.browser, Self.normalizedWebURL(value.url))
        case .terminal(let value): .terminal(value.session)
        case .workingDirectory(let path): .workingDirectory(Self.normalizedPath(path))
        case .repository(let value): .repository(value.identity)
        case .branch(let repository, let name): .branch(repository, name)
        case .file(let value): .file(FileIdentity(path: Self.normalizedPath(value.path)))
        }
    }

    public var kind: ResourceKind {
        switch self {
        case .application: .application
        case .window: .window
        case .browserPage: .browserPage
        case .terminal: .terminal
        case .workingDirectory: .workingDirectory
        case .repository: .repository
        case .branch: .branch
        case .file: .file
        }
    }

    private static func normalizedWebURL(_ raw: String) -> String {
        guard var url = URLComponents(string: raw) else { return raw }
        url.scheme = url.scheme?.lowercased()
        url.host = url.host?.lowercased()
        if (url.scheme == "https" && url.port == 443) || (url.scheme == "http" && url.port == 80) { url.port = nil }
        if url.path.isEmpty { url.path = "/" }
        return url.string ?? raw
    }

    // Lexical only: filesystem aliases and symlinks are resolved by their adapters.
    private static func normalizedPath(_ path: String) -> String {
        guard path.hasPrefix("/") else { return path }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
