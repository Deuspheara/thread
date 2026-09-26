import Foundation
import Testing
import ThreadDomain
@testable import ThreadBrowser

struct BrowserBoundaryTests {
    @Test func urlRedactionAndPrivateExclusionHappenBeforeDomainEvents() throws {
        let message = sample()
        var registry = BrowserConnectionRegistry()
        let event = try registry.normalize(JSONEncoder().encode(message), at: .distantPast)
        guard case .browserTabActivated(let tab) = event else { Issue.record("Expected activation"); return }
        #expect(tab.url == "https://example.com/docs")
        #expect(tab.domain == "example.com")
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        object["isPrivate"] = true
        object["sequence"] = 2
        #expect(try registry.normalize(JSONSerialization.data(withJSONObject: object), at: .distantPast) == nil)
    }

    @Test func unsafeSchemesCredentialsAndInvalidIDsAreRejected() throws {
        let policy = BrowserURLPolicy()
        for url in ["file:///private/data", "javascript:alert(1)", "https://name:secret@example.com/", "about:blank", "https://example.com/\nsecret"] {
            #expect(policy.sanitize(url) == nil)
        }
        let message = sample(tab: -1)
        #expect(throws: (any Error).self) { try message.sanitized() }
    }

    @Test func connectionsHaveIndependentSequencesAndDisconnectedOnesStayClosed() throws {
        var registry = BrowserConnectionRegistry()
        let first = sample()
        let second = sample()
        #expect(try registry.normalize(JSONEncoder().encode(first), at: .distantPast) != nil)
        #expect(try registry.normalize(JSONEncoder().encode(first), at: .distantPast) == nil)
        #expect(try registry.normalize(JSONEncoder().encode(second), at: .distantPast) != nil)
        let end = BrowserMessage(kind: .disconnected, browser: .chrome, connection: first.connection, sequence: 2)
        #expect(try registry.normalize(JSONEncoder().encode(end), at: .distantPast) == .browserDisconnected(BrowserConnectionIdentity(rawValue: first.connection)))
        let late = BrowserMessage(kind: .focusCleared, browser: .chrome, connection: first.connection, sequence: 3)
        #expect(try registry.normalize(JSONEncoder().encode(late), at: .distantPast) == nil)
    }

    @Test func closureDiscardsUnexpectedSensitiveMetadata() throws {
        let closed = BrowserMessage(kind: .closed, browser: .chrome, connection: UUID(), sequence: 1, tabID: 7,
                                    url: "https://example.com/?secret", title: "unnecessary")
        let safe = try closed.sanitized()
        let result = try #require(safe)
        #expect(result.url == nil)
        #expect(result.title == nil)
    }

    @Test func nativeApplicationIdentitySurvivesNormalizationAndCanReplaceUntrustedIdentity() throws {
        let identity = ApplicationIdentity(bundleIdentifier: "com.google.Chrome.canary")
        let message = sample().identified(by: identity)
        var registry = BrowserConnectionRegistry()
        let event = try registry.normalize(JSONEncoder().encode(message), at: .distantPast)
        guard case .browserTabActivated(let tab) = event else { Issue.record("Expected activation"); return }
        #expect(tab.application == identity)
        #expect(message.identified(by: nil).application == nil)
        #expect(throws: BrowserTransportError.self) {
            try sample().identified(by: ApplicationIdentity(bundleIdentifier: "invalid\nidentifier")).sanitized()
        }
    }

    private func sample(tab: Int64 = 1) -> BrowserMessage {
        BrowserMessage(kind: .activated, browser: .chrome, connection: UUID(), sequence: 1, tabID: tab, windowID: 2,
                       url: "https://example.com/docs?secret=1#token", title: "Docs", active: true)
    }
}
