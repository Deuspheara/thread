import Foundation

public enum RemoteInferencePreferenceError: Error, Sendable { case invalidEndpoint }

/// Represents explicit consent and a public endpoint, never a provider or session credential.
public struct RemoteInferencePreferences: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let endpoint: URL?
    public static let disabled = RemoteInferencePreferences()

    private init() { enabled = false; endpoint = nil }

    public init(enabled: Bool, endpoint: URL?) throws {
        if let endpoint {
            let raw = endpoint.absoluteString
            guard raw.utf8.count <= 2048, raw.utf8.allSatisfy({ (33...126).contains($0) }),
                  let url = URLComponents(url: endpoint, resolvingAgainstBaseURL: false), url.scheme == "https",
                  let host = url.host, !host.isEmpty, url.port.map({ (1...65535).contains($0) }) ?? true,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
                throw RemoteInferencePreferenceError.invalidEndpoint
            }
        } else if enabled { throw RemoteInferencePreferenceError.invalidEndpoint }
        self.enabled = enabled
        self.endpoint = endpoint
    }
}
