import Foundation
import Darwin
import Testing
import ThreadDomain
@testable import ThreadBrowser

@MainActor
struct BrowserRestoreTransportTests {
    @Test func abandonedSocketDoesNotClaimLiveRestoreCapability() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/br-" + String(UUID().uuidString.prefix(8)))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let endpoint = directory.appendingPathComponent("s")
        let descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
        #expect(descriptor >= 0)
        let address = try UnixSocketAddress(path: endpoint.path)
        let bound = address.data.withUnsafeBytes { bytes in
            Darwin.bind(descriptor, bytes.baseAddress?.assumingMemoryBound(to: sockaddr.self), socklen_t(bytes.count))
        }
        #expect(bound == 0)
        #expect(chmod(endpoint.path, 0o600) == 0)
        #expect(BrowserMessageSender().isAvailable(at: endpoint))
        close(descriptor)
        #expect(!BrowserMessageSender().isAvailable(at: endpoint))
    }

    @Test func connectedAdapterWaitsForCorrelatedReplyAndCleansReplyEndpoint() async throws {
        let directory = URL(fileURLWithPath: "/private/tmp/br-" + String(UUID().uuidString.prefix(8)))
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = UUID()
        let host = BrowserRestoreHost(directory: directory) { data in
            let command = try JSONDecoder().decode(BrowserRestoreCommand.self, from: data)
            let reply = BrowserRestoreReply(id: command.id, connection: command.connection, outcome: .focused)
            try BrowserMessageSender().sendControl(JSONEncoder().encode(reply), to: BrowserRestoreEndpoint(root: directory).reply(command.id))
        }
        try host.connect(connection)
        let restorer = BrowserTabRestorer(directory: directory)
        let resource = Resource.browserPage(BrowserTabContext(
            identity: BrowserTabIdentity(connection: BrowserConnectionIdentity(rawValue: connection), tab: 7),
            browser: .chrome, window: 1, url: "https://example.com/docs", domain: "example.com", title: "Docs", isActive: true))
        #expect(await restorer.capability(for: resource) == .partial)
        #expect(try await restorer.restore(resource).outcome == .restored)
        let replies = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("r").path)
        #expect(replies.isEmpty)
        host.stop()
        #expect(await restorer.capability(for: resource) == .unavailable)
    }
}
