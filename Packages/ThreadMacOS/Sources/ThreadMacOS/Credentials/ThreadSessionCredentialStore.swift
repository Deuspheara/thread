import Foundation
import Security
import LocalAuthentication

public enum SessionCredentialError: Error, Sendable, Equatable {
    case invalidEndpoint, invalidCredential, missing, accessDenied, unavailable
}

/// Stores only independent Thread session credentials scoped to an exact backend endpoint.
public actor ThreadSessionCredentialStore {
    private let account: String
    private let operations: KeychainOperations

    public init(endpoint: URL) throws {
        try self.init(endpoint: endpoint, operations: .system)
    }

    init(endpoint: URL, operations: KeychainOperations) throws {
        let raw = endpoint.absoluteString
        guard raw.utf8.count <= 2048, raw.utf8.allSatisfy({ (33...126).contains($0) }),
              let url = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              url.port.map({ (1...65535).contains($0) }) ?? true,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw SessionCredentialError.invalidEndpoint
        }
        account = raw
        self.operations = operations
    }

    public func credential() throws -> String {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = operations.read(query)
        if status == errSecItemNotFound { throw SessionCredentialError.missing }
        try requireSuccess(status)
        guard let data, data.count <= 128, let token = String(data: data, encoding: .utf8) else {
            throw SessionCredentialError.invalidCredential
        }
        try validate(token)
        return token
    }

    public func save(_ token: String) throws {
        try validate(token)
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        let status = operations.update(identity, attributes)
        if status != errSecItemNotFound { try requireSuccess(status); return }
        var item = identity.merging(attributes) { _, new in new }
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = operations.add(item)
        if added == errSecDuplicateItem { try requireSuccess(operations.update(identity, attributes)) }
        else { try requireSuccess(added) }
    }

    public func remove() throws {
        let status = operations.delete(identity)
        if status != errSecItemNotFound { try requireSuccess(status) }
    }

    private var identity: [String: Any] {
        let authentication = LAContext()
        authentication.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.thread.desktop.decision-session",
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false,
         kSecUseAuthenticationContext as String: authentication]
    }

    private func validate(_ token: String) throws {
        let alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
        guard (32...128).contains(token.utf8.count), !token.hasPrefix("sk-or-"),
              token.unicodeScalars.allSatisfy({ alphabet.unicodeScalars.contains($0) }) else {
            throw SessionCredentialError.invalidCredential
        }
    }

    private func requireSuccess(_ status: OSStatus) throws {
        if status == errSecSuccess { return }
        if status == errSecAuthFailed || status == errSecInteractionNotAllowed {
            throw SessionCredentialError.accessDenied
        }
        throw SessionCredentialError.unavailable
    }
}
