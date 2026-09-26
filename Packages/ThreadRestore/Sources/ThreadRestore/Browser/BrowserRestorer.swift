import AppKit
import ThreadDomain

/// Reopens a public URL in its recorded browser without claiming exact tab restoration.
public struct BrowserRestorer: ResourceRestorer {
    public init() {}

    @MainActor public func capability(for resource: Resource) async -> RestoreCapability {
        guard case .browserPage(let page) = resource, safeURL(page.url) != nil,
              applicationURL(page) != nil else { return .unavailable }
        return .resource
    }

    @MainActor public func restore(_ resource: Resource) async throws -> RestoreResult {
        guard case .browserPage(let page) = resource, let url = safeURL(page.url),
              let app = applicationURL(page) else {
            return RestoreResult(resource: resource.id, capability: .unavailable, outcome: .unavailable)
        }
        try Task.checkCancellation()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
        return RestoreResult(resource: resource.id, capability: .resource, outcome: .restored)
    }

    func safeURL(_ raw: String) -> URL? {
        guard let components = URLComponents(string: raw),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        return components.url
    }

    @MainActor private func applicationURL(_ page: BrowserTabContext) -> URL? {
        if let application = page.application {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: application.bundleIdentifier)
        }
        let identifier: String
        switch page.browser {
        case .chromium: identifier = "org.chromium.Chromium"
        case .chrome: identifier = "com.google.Chrome"
        case .brave: identifier = "com.brave.Browser"
        case .edge: identifier = "com.microsoft.edgemac"
        case .safari: identifier = "com.apple.Safari"
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
    }
}
