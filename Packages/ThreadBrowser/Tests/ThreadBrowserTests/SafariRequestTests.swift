import Foundation
import Testing
@testable import ThreadBrowser

struct SafariRequestTests {
    @Test func rejectsWrongBrowserOversizedAndPrivateRequestsBeforeTransport() throws {
        let bridge = SafariRequestForwarder(endpoint: URL(fileURLWithPath: "/nonexistent/thread.sock"))
        let chrome = BrowserMessage(kind: .connected, browser: .chrome, connection: UUID(), sequence: 1)
        #expect(throws: BrowserTransportError.self) { try bridge.forward(JSONEncoder().encode(chrome)) }
        #expect(throws: BrowserTransportError.self) { try bridge.forward(Data(repeating: 32, count: 16_385)) }
        let safari = BrowserMessage(kind: .connected, browser: .safari, connection: UUID(), sequence: 2)
        let json = String(decoding: try JSONEncoder().encode(safari), as: UTF8.self)
        let privateData = Data(json.replacingOccurrences(of: "\"isPrivate\":false", with: "\"isPrivate\":true").utf8)
        let reply = try bridge.forward(privateData)
        #expect(!reply.forwarded)
        #expect(reply.instance == nil)
    }

    @Test @MainActor func safariRequestReachesSocketWithRedactedMetadataAndAcknowledgment() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/tsf-" + UUID().uuidString.prefix(8))
        defer { try? FileManager.default.removeItem(at: directory) }
        let endpoint = directory.appendingPathComponent("b.sock")
        var received: BrowserMessage?
        let listener = UnixDatagramListener { data in
            do { received = try JSONDecoder().decode(BrowserMessage.self, from: data) }
            catch { Issue.record("Invalid Safari datagram") }
        }
        try listener.start(at: endpoint)
        defer { listener.stop() }
        let request = BrowserMessage(kind: .activated, browser: .safari, connection: UUID(), sequence: 3,
                                     tabID: 1, windowID: 2, url: "https://example.com/path?secret=x#fragment",
                                     title: "Example", active: true)
        let reply = try SafariRequestForwarder(endpoint: endpoint).forward(JSONEncoder().encode(request))
        #expect(reply.forwarded)
        #expect(reply.sequence == 3)
        #expect(reply.instance != nil)
        let deadline = Date().addingTimeInterval(2)
        while received == nil, Date() < deadline { CFRunLoopRunInMode(.defaultMode, 0.02, true) }
        #expect(received?.browser == .safari)
        #expect(received?.url == "https://example.com/path")
    }
    @Test @MainActor func restoreReplyReachesOnlyItsRequestEndpoint() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/tsf-" + UUID().uuidString.prefix(8))
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = UUID().uuidString.lowercased()
        let endpoint = directory.appendingPathComponent("Browser/activity.sock")
        let replyURL = directory.appendingPathComponent("Browser/r/\(request)/s")
        var received: BrowserRestoreReply?
        let listener = UnixDatagramListener { data in
            received = try? JSONDecoder().decode(BrowserRestoreReply.self, from: data)
        }
        try listener.start(at: replyURL)
        defer { listener.stop() }
        let reply = BrowserRestoreReply(id: request, connection: UUID().uuidString.lowercased(), outcome: .focused)
        let forwarded = try SafariRequestForwarder(endpoint: endpoint).forwardRestoreReply(JSONEncoder().encode(reply))
        #expect(forwarded.id == request)
        let deadline = Date().addingTimeInterval(2)
        while received == nil, Date() < deadline { CFRunLoopRunInMode(.defaultMode, 0.02, true) }
        #expect(received?.id == request)
        #expect(received?.outcome == .focused)
    }

}
