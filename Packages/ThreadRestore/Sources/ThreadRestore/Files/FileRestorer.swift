import AppKit
import ThreadDomain

/// Sends existing documents to the per-Thread application, using default associations only when intent is unknown.
public struct FileRestorer: ResourceRestorer {
    private let applicationURL: @MainActor @Sendable (String) -> URL?
    private let openDocument: @MainActor @Sendable (URL, URL?) async throws -> Bool
    public init() {
        applicationURL = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        openDocument = { url, app in
            if let app {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
                return true
            }
            return NSWorkspace.shared.open(url)
        }
    }
    init(applicationURL: @escaping @MainActor @Sendable (String) -> URL?,
         openDocument: @escaping @MainActor @Sendable (URL, URL?) async throws -> Bool) {
        self.applicationURL = applicationURL; self.openDocument = openDocument
    }
    public func capability(for resource: Resource) async -> RestoreCapability {
        fileURL(resource) == nil ? .unavailable : .resource
    }
    @MainActor public func capability(for target: RestoreTarget) async -> RestoreCapability {
        guard fileURL(target.resource) != nil else { return .unavailable }
        if let app = target.application, (!app.isValid || applicationURL(app.identity.bundleIdentifier) == nil) { return .unavailable }
        return .resource
    }
    public func restore(_ resource: Resource) async throws -> RestoreResult {
        try await restore(RestoreTarget(resource: resource))
    }
    @MainActor public func restore(_ target: RestoreTarget) async throws -> RestoreResult {
        let app = target.application.flatMap { applicationURL($0.identity.bundleIdentifier) }
        guard let url = fileURL(target.resource), target.application == nil || app != nil else {
            return RestoreResult(resource: target.resource.id, capability: .unavailable, outcome: .unavailable,
                application: target.application, explanation: "The item or preferred application is unavailable. Choose an installed application in Details.")
        }
        try Task.checkCancellation()
        do {
            let opened = try await openDocument(url, app)
            return RestoreResult(resource: target.resource.id, capability: .resource, outcome: opened ? .restored : .failed,
                application: target.application, explanation: opened
                    ? "Open request accepted. Editor tabs and cursor position are not restored."
                    : "The application did not accept the open request. Check the item before retrying.")
        } catch is CancellationError { throw CancellationError() }
        catch {
            return RestoreResult(resource: target.resource.id, capability: .resource, outcome: .failed,
                application: target.application, explanation: "The document open request failed. Check the application and file before retrying.")
        }
    }
    private func fileURL(_ resource: Resource) -> URL? {
        guard case .file(let file) = resource, file.path.hasPrefix("/"),
              !file.path.utf8.contains(0), FileManager.default.fileExists(atPath: file.path) else { return nil }
        return URL(fileURLWithPath: file.path)
    }
}
