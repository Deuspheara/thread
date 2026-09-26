import Foundation

/// Allows HTTP(S) resources while removing sensitive URL components before local IPC or storage.
public struct BrowserURLPolicy: Sendable {
    public init() {}
    public func sanitize(_ value: String) -> URL? {
        guard value.utf8.count <= 4096, !value.unicodeScalars.contains(where: { $0.value < 32 }),
              var parts = URLComponents(string: value),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = host.lowercased()
        parts.query = nil
        parts.fragment = nil
        if parts.path.isEmpty { parts.path = "/" }
        return parts.url
    }
}
