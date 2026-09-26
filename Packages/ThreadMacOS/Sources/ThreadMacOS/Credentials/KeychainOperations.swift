import Foundation
import Security
import OSLog

/// Keeps Security query dictionaries at the adapter boundary with a replaceable test seam.
struct KeychainOperations: Sendable {
    let read: @Sendable ([String: Any]) -> (OSStatus, Data?)
    let add: @Sendable ([String: Any]) -> OSStatus
    let update: @Sendable ([String: Any], [String: Any]) -> OSStatus
    let delete: @Sendable ([String: Any]) -> OSStatus

    static let system = KeychainOperations(read: { query in
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (checked(status, operation: "read"), result as? Data)
    }, add: { checked(SecItemAdd($0 as CFDictionary, nil), operation: "add") },
       update: { checked(SecItemUpdate($0 as CFDictionary, $1 as CFDictionary), operation: "update") },
       delete: { checked(SecItemDelete($0 as CFDictionary), operation: "delete") })
    private static func checked(_ status: OSStatus, operation: StaticString) -> OSStatus {
        if status != errSecSuccess && status != errSecItemNotFound {
            Logger(subsystem: "app.thread.desktop", category: "credentials")
                .error("Keychain operation \(operation, privacy: .public) failed with status \(status, privacy: .public)")
        }
        return status
    }
}
