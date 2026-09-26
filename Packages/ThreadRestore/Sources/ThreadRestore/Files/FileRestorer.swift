import AppKit
import ThreadDomain

/// Reopens an existing local file or project with its registered application.
public struct FileRestorer: ResourceRestorer {
    public init() {}

    public func capability(for resource: Resource) async -> RestoreCapability {
        fileURL(resource) == nil ? .unavailable : .resource
    }

    @MainActor public func restore(_ resource: Resource) async throws -> RestoreResult {
        guard let url = fileURL(resource) else {
            return RestoreResult(resource: resource.id, capability: .unavailable, outcome: .unavailable)
        }
        try Task.checkCancellation()
        let opened = NSWorkspace.shared.open(url)
        return RestoreResult(resource: resource.id, capability: .resource, outcome: opened ? .restored : .failed)
    }

    private func fileURL(_ resource: Resource) -> URL? {
        guard case .file(let file) = resource, file.path.hasPrefix("/"),
              !file.path.utf8.contains(0), FileManager.default.fileExists(atPath: file.path) else { return nil }
        return URL(fileURLWithPath: file.path)
    }
}
