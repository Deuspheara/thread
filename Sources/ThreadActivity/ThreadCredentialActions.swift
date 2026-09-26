import Foundation
import ThreadMacOS

/// Injects endpoint-scoped credential operations into application configuration.
public struct ThreadCredentialActions: Sendable {
    public let read: @Sendable (URL) async throws -> String
    public let save: @Sendable (URL, String) async throws -> Void
    public let remove: @Sendable (URL) async throws -> Void

    public init(read: @escaping @Sendable (URL) async throws -> String,
                save: @escaping @Sendable (URL, String) async throws -> Void,
                remove: @escaping @Sendable (URL) async throws -> Void) {
        self.read = read; self.save = save; self.remove = remove
    }

    public static let keychain = ThreadCredentialActions(read: {
        try await ThreadSessionCredentialStore(endpoint: $0).credential()
    }, save: { try await ThreadSessionCredentialStore(endpoint: $0).save($1) },
       remove: { try await ThreadSessionCredentialStore(endpoint: $0).remove() })
}
