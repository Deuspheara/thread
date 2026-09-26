import Foundation
import Testing
import ThreadDomain
@testable import ThreadBrowser

struct BrowserSocketTests {
    @Test @MainActor func nativePayloadReachesListenerAndNormalizesWithoutSensitiveURLParts() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/tbr-" + UUID().uuidString.prefix(8))
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("b.sock")
        var observed: ActivityEventKind?
        var registry = BrowserConnectionRegistry()
        let listener = UnixDatagramListener { data in
            do { observed = try registry.normalize(data, at: .distantPast) }
            catch { Issue.record("Browser datagram did not normalize") }
        }
        try listener.start(at: url)
        defer { listener.stop() }
        let message = BrowserMessage(kind: .activated, browser: .chrome, connection: UUID(), sequence: 1, tabID: 1, windowID: 2,
                                     url: "https://example.com/?token=secret", title: "Example", active: true)
        let generation = try BrowserMessageSender().send(message, to: url)
        #expect(generation != nil)
        let deadline = Date().addingTimeInterval(2)
        while observed == nil, Date() < deadline { CFRunLoopRunInMode(.defaultMode, 0.02, true) }
        guard case .browserTabActivated(let tab) = observed else { Issue.record("No tab arrived"); return }
        #expect(tab.url == "https://example.com/")
        #expect(tab.identity.connection.rawValue == message.connection)
    }
}
