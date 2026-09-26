import AppKit
import ThreadDomain

/// Opens a directory in Terminal using document-open events, without sending shell commands.
public struct TerminalRestorer: ResourceRestorer {
    public init() {}

    @MainActor public func capability(for resource: Resource) async -> RestoreCapability {
        guard directoryURL(resource) != nil,
              NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") != nil else { return .unavailable }
        return .partial
    }

    @MainActor public func restore(_ resource: Resource) async throws -> RestoreResult {
        guard let directory = directoryURL(resource),
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            return RestoreResult(resource: resource.id, capability: .unavailable, outcome: .unavailable)
        }
        try Task.checkCancellation()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open([directory], withApplicationAt: terminal, configuration: configuration)
        return RestoreResult(resource: resource.id, capability: .partial, outcome: .restored)
    }

    func directoryURL(_ resource: Resource) -> URL? {
        let path: String
        switch resource {
        case .terminal(let terminal): path = terminal.workingDirectory
        case .workingDirectory(let directory): path = directory
        case .repository(let repository): path = repository.rootPath
        default: return nil
        }
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
