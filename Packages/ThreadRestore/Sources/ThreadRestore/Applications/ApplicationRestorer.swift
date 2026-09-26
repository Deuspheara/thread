import AppKit
import ThreadDomain

/// Activates or launches an installed application by bundle identity.
public struct ApplicationRestorer: ResourceRestorer {
    public init() {}

    @MainActor public func capability(for resource: Resource) async -> RestoreCapability {
        guard case .application(let app) = resource,
              NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.identity.bundleIdentifier) != nil else { return .unavailable }
        return .activateOnly
    }

    @MainActor public func restore(_ resource: Resource) async throws -> RestoreResult {
        guard case .application(let app) = resource,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.identity.bundleIdentifier) else {
            return RestoreResult(resource: resource.id, capability: .unavailable, outcome: .unavailable)
        }
        try Task.checkCancellation()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return RestoreResult(resource: resource.id, capability: .activateOnly, outcome: .restored)
    }
}
