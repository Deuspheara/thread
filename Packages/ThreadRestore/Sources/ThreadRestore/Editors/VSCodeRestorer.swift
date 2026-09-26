import AppKit
import ThreadDomain

/// Reopens a saved VS Code workspace in VS Code using a native document-open event.
public struct VSCodeRestorer: ResourceRestorer {
    public init() {}

    @MainActor public func capability(for resource: Resource) async -> RestoreCapability {
        guard workspaceURL(resource) != nil,
              NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") != nil else { return .unavailable }
        return .resource
    }

    @MainActor public func restore(_ resource: Resource) async throws -> RestoreResult {
        guard let workspace = workspaceURL(resource),
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") else {
            return RestoreResult(resource: resource.id, capability: .unavailable, outcome: .unavailable)
        }
        try Task.checkCancellation()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open([workspace], withApplicationAt: app, configuration: configuration)
        return RestoreResult(resource: resource.id, capability: .resource, outcome: .restored)
    }

    func workspaceURL(_ resource: Resource) -> URL? {
        guard case .file(let file) = resource, file.path.hasPrefix("/"), !file.path.utf8.contains(0) else { return nil }
        let url = URL(fileURLWithPath: file.path)
        guard url.pathExtension.lowercased() == "code-workspace" else { return nil }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &directory), !directory.boolValue else { return nil }
        return url
    }
}
