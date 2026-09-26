import Foundation
import SafariServices
import ThreadDomain

/// Dispatches a scoped restore request to the installed Safari web extension.
@MainActor
public final class SafariTabRestorer: ResourceRestorer {
    private let directory: URL
    private let extensionIdentifier: String
    private let connected: @MainActor @Sendable (UUID) -> Bool

    public init(directory: URL, extensionIdentifier: String,
                connected: @escaping @MainActor @Sendable (UUID) -> Bool) {
        self.directory = directory
        self.extensionIdentifier = extensionIdentifier
        self.connected = connected
    }

    public func capability(for resource: Resource) async -> RestoreCapability {
        guard case .browserPage(let page) = resource, page.browser == .safari,
              connected(page.identity.connection.rawValue) else { return .unavailable }
        return .partial
    }

    public func restore(_ resource: Resource) async throws -> RestoreResult {
        guard case .browserPage(let page) = resource, page.browser == .safari,
              connected(page.identity.connection.rawValue) else {
            return RestoreResult(resource: resource.id, capability: .unavailable, outcome: .unavailable)
        }
        let command = BrowserRestoreCommand(connection: page.identity.connection.rawValue, url: page.url,
                                            tabID: page.identity.tab)
        let request = BrowserRestoreRequest(endpoint: BrowserRestoreEndpoint(root: directory).reply(command.id), command: command)
        let extensionIdentifier = self.extensionIdentifier
        let reply = try await request.send { data in
            guard let info = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw BrowserTransportError.invalidMessage
            }
            try await SFSafariApplication.dispatchMessage(withName: "restoreTab",
                toExtensionWithIdentifier: extensionIdentifier, userInfo: info)
        }
        let outcome: RestoreOutcome
        switch reply.outcome {
        case .focused, .reopened: outcome = .restored
        case .refused, .busy, .failed: outcome = .failed
        }
        return RestoreResult(resource: resource.id, capability: .partial, outcome: outcome)
    }
}
