import Foundation
import Security
import LocalAuthentication
import Testing
@testable import ThreadMacOS

struct ThreadSessionCredentialTests {
    private let token = String(repeating: "a", count: 43)

    @Test func endpointScopingAndProviderKeysFailClosed() async throws {
        for raw in ["http://thread.example/v1/decisions", "https://user:pass@thread.example/",
                    "https://thread.example/?secret=1", "https://thread.example/#fragment", "https://thread.example:99999/"] {
            #expect(throws: SessionCredentialError.invalidEndpoint) {
                try ThreadSessionCredentialStore(endpoint: URL(string: raw)!, operations: untouched)
            }
        }
        let store = try ThreadSessionCredentialStore(endpoint: URL(string: "https://thread.example/v1/decisions")!, operations: untouched)
        for invalid in ["sk-or-" + token, "short", token + "\n", token + "/", String(repeating: "a", count: 129)] {
            await #expect(throws: SessionCredentialError.invalidCredential) { try await store.save(invalid) }
        }
    }

    @Test func queriesBindToTheExactEndpointAndDisableSynchronizationAndPrompts() async throws {
        for raw in ["https://one.example/v1/decisions", "https://two.example/v1/decisions", "https://one.example/other"] {
            let expectedToken = token
            let operations = KeychainOperations(read: { query in
                #expect(query[kSecAttrAccount as String] as? String == raw)
                #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
                #expect((query[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed == true)
                return (errSecSuccess, Data(expectedToken.utf8))
            }, add: { _ in Issue.record("Unexpected add"); return errSecParam },
               update: { _, _ in Issue.record("Unexpected update"); return errSecParam },
               delete: { _ in errSecItemNotFound })
            let store = try ThreadSessionCredentialStore(endpoint: URL(string: raw)!, operations: operations)
            #expect(try await store.credential() == token)
            try await store.remove()
        }
    }

    @Test func missingDeniedAndMalformedRecordsReturnTypedFailures() async throws {
        for (status, data, expected) in [(errSecItemNotFound, nil, SessionCredentialError.missing),
                                         (errSecInteractionNotAllowed, nil, .accessDenied),
                                         (errSecParam, nil, .unavailable),
                                         (errSecSuccess, Data("sk-or-invalid-provider-key".utf8), .invalidCredential)] {
            let operations = KeychainOperations(read: { _ in (status, data) }, add: untouched.add,
                update: untouched.update, delete: untouched.delete)
            let store = try ThreadSessionCredentialStore(endpoint: URL(string: "https://thread.example/")!, operations: operations)
            await #expect(throws: expected) { try await store.credential() }
        }
    }

    @Test func saveUsesDeviceLocalAttributesAndDoesNotHideWriteFailures() async throws {
        let expectedToken = token
        for status in [errSecSuccess, errSecItemNotFound, errSecAuthFailed] {
            let operations = KeychainOperations(read: untouched.read, add: { item in
                #expect(status == errSecItemNotFound)
                #expect(item[kSecValueData as String] as? Data == Data(expectedToken.utf8))
                #expect(item[kSecAttrSynchronizable as String] as? Bool == false)
                #expect(item[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
                return errSecSuccess
            }, update: { query, attributes in
                #expect(query[kSecAttrAccount as String] as? String == "https://thread.example/v1/decisions")
                #expect(attributes[kSecValueData as String] as? Data == Data(expectedToken.utf8))
                return status
            }, delete: untouched.delete)
            let store = try ThreadSessionCredentialStore(endpoint: URL(string: "https://thread.example/v1/decisions")!, operations: operations)
            if status == errSecAuthFailed {
                await #expect(throws: SessionCredentialError.accessDenied) { try await store.save(expectedToken) }
            } else { try await store.save(expectedToken) }
        }
    }

    private var untouched: KeychainOperations {
        KeychainOperations(read: { _ in Issue.record("Unexpected Keychain read"); return (errSecParam, nil) },
            add: { _ in Issue.record("Unexpected Keychain add"); return errSecParam },
            update: { _, _ in Issue.record("Unexpected Keychain update"); return errSecParam },
            delete: { _ in Issue.record("Unexpected Keychain delete"); return errSecParam })
    }
}
