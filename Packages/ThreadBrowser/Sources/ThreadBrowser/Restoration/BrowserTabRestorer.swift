import Foundation
import ThreadDomain

/// Restores through a connected extension; uncertain acknowledgments never trigger duplicate URL reopening.
@MainActor
public final class BrowserTabRestorer: ResourceRestorer {
    private let endpoints: BrowserRestoreEndpoint
    public init(directory: URL) { endpoints = BrowserRestoreEndpoint(root: directory) }

    public func capability(for resource: Resource) async -> RestoreCapability {
        guard case .browserPage(let page) = resource, page.browser != .safari else { return .unavailable }
        let request = command(page)
        guard (try? request.validate()) != nil,
              BrowserMessageSender().isAvailable(at: endpoints.host(request.connection)) else { return .unavailable }
        return .partial
    }

    public func restore(_ resource: Resource) async throws -> RestoreResult {
        guard case .browserPage(let page) = resource, page.browser != .safari else {
            return RestoreResult(resource: resource.id, capability: .unavailable, outcome: .unavailable)
        }
        let command = command(page)
        let request = BrowserRestoreRequest(endpoint: endpoints.reply(command.id), command: command)
        let reply = try await request.send(to: endpoints.host(command.connection))
        let outcome: RestoreOutcome
        switch reply.outcome {
        case .focused, .reopened: outcome = .restored
        case .refused, .busy, .failed: outcome = .failed
        }
        return RestoreResult(resource: resource.id, capability: reply.outcome == .focused ? .partial : .resource, outcome: outcome)
    }

    private func command(_ page: BrowserTabContext) -> BrowserRestoreCommand {
        BrowserRestoreCommand(connection: page.identity.connection.rawValue, url: page.url, tabID: page.identity.tab)
    }
}
