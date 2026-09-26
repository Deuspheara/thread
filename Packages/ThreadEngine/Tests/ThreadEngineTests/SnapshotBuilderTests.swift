import Foundation
import Testing
import ThreadDomain
import ThreadEngine

struct SnapshotBuilderTests {
    @Test func snapshotExcludesProvisionalAndBoundsResourcesWhilePreservingPinnedMetadata() throws {
        let epoch = Date(timeIntervalSince1970: 100)
        let id = ThreadID(rawValue: UUID())
        func edge(_ name: String, _ second: Double, pinned: Bool = false, status: MembershipStatus = .confirmed) -> ThreadResource {
            ThreadResource(resource: .workingDirectory("/work/" + name), confidence: 0.97, firstSeen: epoch,
                lastSeen: epoch.addingTimeInterval(second), source: ActivitySourceID(rawValue: "test"), status: status, pinned: pinned)
        }
        let detail = ThreadDetail(thread: ThreadDomain.Thread(id: id, title: "Work", createdAt: epoch, lastActiveAt: epoch),
            resources: [edge("pinned", 0, pinned: true), edge("old", 1), edge("new", 2), edge("uncertain", 3, status: .provisional)])
        let snapshot = try #require(SnapshotBuilder(maximumResources: 2).build(detail, at: epoch.addingTimeInterval(4)))
        #expect(snapshot.resources.map { $0.resource.id } == [.workingDirectory("/work/pinned"), .workingDirectory("/work/new")])
        #expect(snapshot.capturedAt == epoch.addingTimeInterval(4))
        #expect(snapshot.thread == id)
    }
}
