import Foundation
import Darwin
import ThreadAgentTransport

/// Keeps production storage fixed and confines debug overrides to private fixture directories.
enum AgentStorageLocation {
    static func resolve(debugPath: String?) throws -> URL {
        guard let debugPath else {
            return URL.applicationSupportDirectory.appendingPathComponent("Thread", isDirectory: true)
        }
        #if DEBUG
        let requested = URL(fileURLWithPath: debugPath, isDirectory: true).standardizedFileURL
        guard requested.path.hasPrefix("/"), requested.lastPathComponent == "data" else {
            throw AgentTransportError.invalidMessage
        }
        let parent = requested.deletingLastPathComponent().resolvingSymlinksInPath()
        guard ["/private/tmp", "/tmp"].contains(parent.deletingLastPathComponent().path),
              parent.lastPathComponent.hasPrefix("th-") else { throw AgentTransportError.invalidMessage }
        let attributes = try FileManager.default.attributesOfItem(atPath: parent.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else {
            throw AgentTransportError.invalidMessage
        }
        let directory = parent.appendingPathComponent("data", isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else {
                throw AgentTransportError.invalidMessage
            }
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
        }
        return directory
        #else
        throw AgentTransportError.invalidMessage
        #endif
    }
}
