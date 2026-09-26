import Foundation
import Testing
import ThreadDomain
@testable import ThreadDecisions

struct DecisionPayloadPrivacyTests {
    private let now = Date(timeIntervalSince1970: 100)

    @Test func encodedPayloadOmitsLocalIdentitiesPathsURLsAndCandidateTitles() throws {
        let connection = UUID()
        let thread = ThreadID(rawValue: UUID())
        let page = Resource.browserPage(BrowserTabContext(
            identity: BrowserTabIdentity(connection: BrowserConnectionIdentity(rawValue: connection), tab: 987),
            browser: .chrome, window: 876, url: "https://example.com/private-document?token=secret#fragment",
            domain: "forged.example", title: "PRIVATE PAGE TITLE", isActive: true))
        let resources: [Resource] = [.file(FileIdentity(path: "/Users/private-person/secret-folder/Session.swift")),
            .workingDirectory("/Users/private-person/secret-folder"), page]
        let context = ActivityContext(startedAt: now.addingTimeInterval(-25), endedAt: now,
            resources: resources.map { evidence($0) })
        let candidate = ScoredThreadCandidate(candidate: ThreadCandidate(id: thread, title: "PRIVATE THREAD TITLE",
            lastActiveAt: now.addingTimeInterval(-60), resourceIDs: Set(resources.map(\.id))),
            relevance: 0.8, signals: [.sameFile, .recentActivity])
        let prepared = PrivacyRedactor().redact(DecisionPayloadBuilder().build(context: context, candidates: [candidate]))
        let json = String(decoding: try JSONEncoder().encode(prepared.payload), as: UTF8.self)
        for secret in ["private-person", "secret-folder", "private-document", "token", "secret", "fragment",
                       "PRIVATE", "forged.example", connection.uuidString, thread.rawValue.uuidString, "987", "876"] {
            #expect(!json.contains(secret))
        }
        #expect(prepared.payload.resources[0].label == "Session.swift")
        #expect(prepared.payload.resources[1].label == nil)
        #expect(prepared.payload.resources[2].label == "example.com")
        #expect(prepared.payload.candidates[0].matchingResources == ["r0", "r1", "r2"])
        #expect(prepared.candidateIDs["c0"] == thread)
    }

    @Test func unsafeLabelsAreDroppedAndNumericFieldsAreFiniteAndBounded() throws {
        let samples: [(ResourceKind, String, String?)] = [
            (.browserPage, "https://person:password@example.com/private", nil),
            (.browserPage, "file:///private/file", nil),
            (.browserPage, "https://EXAMPLE.COM/path?secret=1", "example.com"),
            (.repository, "/Users/private-person/dev/HomeControl", "HomeControl"),
            (.branch, "fix/ota-reconnect", "fix/ota-reconnect"),
            (.branch, "/Users/private-person", nil),
            (.branch, "person@example.com", nil),
            (.application, "com.apple.dt.Xcode", "com.apple.dt.Xcode"),
            (.application, "name\nprivate", nil),
            (.file, "/work/person@example.com", nil),
            (.file, "relative/Document.swift", nil),
            (.file, "/work/" + String(repeating: "x", count: 129), nil),
            (.window, "PRIVATE WINDOW TITLE", nil)
        ]
        let draft = DecisionPayloadDraft(seconds: .infinity, resources: samples.map {
            .init(id: .workingDirectory($0.1), kind: $0.0, value: $0.1, seconds: -.infinity)
        }, candidates: [.init(id: ThreadID(rawValue: UUID()), relevance: .nan,
            signals: [.sameFile, .sameFile], matchingResources: [-1, 0, 0, 999], secondsSinceActive: 1e100)])
        let payload = PrivacyRedactor().redact(draft).payload
        #expect(payload.observedSeconds == 0)
        #expect(payload.resources.map(\.label) == samples.map { $0.2 })
        #expect(payload.resources.allSatisfy { $0.observedSeconds == 0 })
        #expect(payload.candidates[0].relevance == 0)
        #expect(payload.candidates[0].secondsSinceActive == 2_592_000)
        #expect(payload.candidates[0].matchingResources == ["r0"])
        #expect(payload.candidates[0].signals == [.sameFile])
        _ = try JSONEncoder().encode(payload)
    }

    @Test func builderDeduplicatesAndCapsResourcesAndCandidateScope() throws {
        let resources = (0..<200).map { Resource.file(FileIdentity(path: "/work/File\($0).swift")) }
        let context = ActivityContext(startedAt: now, endedAt: now,
            resources: (resources + resources).map { evidence($0) })
        let candidates = (0..<20).map { index in
            ScoredThreadCandidate(candidate: ThreadCandidate(id: ThreadID(rawValue: UUID()), title: "Work \(index)",
                lastActiveAt: now, resourceIDs: Set(resources.map(\.id))), relevance: 0.8, signals: [.sameFile])
        }
        let draft = DecisionPayloadBuilder().build(context: context, candidates: [candidates[0]] + candidates)
        let prepared = PrivacyRedactor().redact(draft)
        #expect(try JSONEncoder().encode(prepared.payload).count < 65_536)
        #expect(prepared.payload.resources.count == 128)
        #expect(prepared.payload.candidates.count == 8)
        #expect(prepared.candidateIDs.count == 8)
        #expect(Set(prepared.candidateIDs.values).count == 8)
        #expect(prepared.payload.candidates.allSatisfy { $0.matchingResources.count == 128 })
    }

    private func evidence(_ resource: Resource) -> ResourceEvidence {
        ResourceEvidence(resource: resource, firstSeen: now.addingTimeInterval(-25), lastSeen: now,
            source: ActivitySourceID(rawValue: "private-source"))
    }
}
