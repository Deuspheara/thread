import Foundation

/// Validates public release configuration before the updater can be created.
struct UpdateConfiguration {
    init?(feed: String?, publicKey: String?) {
        guard let feed, feed.utf8.count <= 2048, feed.utf8.allSatisfy({ (33...126).contains($0) }), let url = URLComponents(string: feed),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              url.port.map({ (1...65535).contains($0) }) ?? true,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              let publicKey, let key = Data(base64Encoded: publicKey), key.count == 32,
              key.base64EncodedString() == publicKey else { return nil }
    }
}
