import Foundation
import Testing
import ThreadDomain
import ThreadEngine

struct ThreadReadingTests {
    @Test func recentCapDoesNotHideArchivedDetailsOrOlderDestinations() async throws {
        let graph = ThreadGraphStore()
        let time = Date(timeIntervalSince1970: 100)
        let nodes = (0..<25).map { index in
            ThreadDetail(thread: ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: "Work \(index)",
                createdAt: time, lastActiveAt: time.addingTimeInterval(Double(index)), isArchived: index == 0), resources: [])
        }
        try await graph.restore(ThreadGraphState(threads: nodes, corrections: []))
        let recent = await graph.recentSummaries(limit: 1000)
        #expect(recent.count == 20)
        #expect(!recent.contains { $0.thread.id == nodes[1].thread.id })
        #expect(try await graph.detailPage(nodes[0].thread.id, after: nil, limit: 64)?.thread.isArchived == true)
        let targets = await graph.destinations(query: "Work 1", excluding: nodes[24].thread.id, limit: 1000)
        #expect(targets.contains { $0.id == nodes[1].thread.id })
        #expect(await graph.destinations(query: "", excluding: nodes[24].thread.id, limit: 1000).count == 20)
        #expect(!targets.contains { $0.isArchived || $0.id == nodes[24].thread.id })
    }

    @Test func resourcePagesAreBoundedCompleteAndRejectAnUnknownCursor() async throws {
        let graph = ThreadGraphStore()
        let time = Date(timeIntervalSince1970: 100)
        let thread = ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: "Many resources", createdAt: time, lastActiveAt: time)
        let edges = (0..<70).map { index in
            ThreadResource(resource: .workingDirectory("/fixture/\(index)"), confidence: 0.99,
                firstSeen: time.addingTimeInterval(Double(index)), lastSeen: time.addingTimeInterval(Double(index)),
                source: ActivitySourceID(rawValue: "fixture"), status: .confirmed)
        }
        try await graph.restore(ThreadGraphState(threads: [ThreadDetail(thread: thread, resources: edges)], corrections: []))
        let first = try #require(try await graph.detailPage(thread.id, after: nil, limit: 1000))
        #expect(first.resources.count == 64)
        #expect(first.totalResourceCount == 70)
        let cursor = try #require(first.next)
        let second = try #require(try await graph.detailPage(thread.id, after: cursor, limit: 64))
        #expect(second.resources.count == 6)
        #expect(second.next == nil)
        #expect(Set((first.resources + second.resources).map { $0.resource.id }).count == 70)
        await #expect(throws: ThreadReadError.stalePage) {
            try await graph.detailPage(thread.id, after: .workingDirectory("/missing"), limit: 64)
        }
    }
}
