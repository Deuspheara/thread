import Foundation
import Testing
import ThreadDomain
@testable import ThreadEngine

struct ThreadMergePlanTests {
    @Test func newerWeakEvidenceCannotReplaceConfirmedRestorationMetadata() throws {
        let first = Date(timeIntervalSince1970: 100), last = Date(timeIntervalSince1970: 120)
        let identity = ApplicationIdentity(bundleIdentifier: "app.editor")
        let confirmed = ThreadResource(resource: .application(ApplicationContext(identity: identity, name: "Confirmed", processIdentifier: 1)),
            confidence: 0.98, firstSeen: first, lastSeen: first, source: ActivitySourceID(rawValue: "strong"), status: .confirmed, pinned: true)
        let provisional = ThreadResource(resource: .application(ApplicationContext(identity: identity, name: "Provisional", processIdentifier: 2)),
            confidence: 0.75, firstSeen: last, lastSeen: last, source: ActivitySourceID(rawValue: "weak"), status: .provisional,
            persistence: .sessionOnly)
        func detail(_ edge: ThreadResource) -> ThreadDetail {
            ThreadDetail(thread: ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: "Work", createdAt: first, lastActiveAt: last),
                         resources: [edge])
        }
        for (source, target) in [(confirmed, provisional), (provisional, confirmed)] {
            let plan = try ThreadMergePlan(source: detail(source), destination: detail(target))
            let merged = try #require(plan.resources[confirmed.resource.id])
            #expect(merged.resource == confirmed.resource)
            #expect(merged.status == .confirmed)
            #expect(merged.confidence == 0.98)
            #expect(merged.pinned)
            #expect(merged.persistence == .durable)
            #expect(merged.firstSeen == first && merged.lastSeen == last)
        }
    }
}
