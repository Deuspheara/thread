import Foundation
import Testing
import ThreadDomain
@testable import ThreadEngine

struct RestoreCancellationTests {
    @Test func cancellationDuringCapabilityCheckPreventsOpeningAndConcurrentRestoreIsRejected() async throws {
        let graph = ThreadGraphStore()
        let id = ThreadID(rawValue: UUID())
        let time = Date(timeIntervalSince1970: 100)
        let resources = ["/one", "/two"].map {
            ThreadResource(resource: .file(FileIdentity(path: $0)), confidence: 1,
                firstSeen: time, lastSeen: time, source: ActivitySourceID(rawValue: "test"), status: .confirmed)
        }
        try await graph.restore(ThreadGraphState(threads: [ThreadDetail(
            thread: ThreadDomain.Thread(id: id, title: "Work", createdAt: time, lastActiveAt: time), resources: resources)], corrections: []))
        let adapter = PausedCapability()
        let focus = RecordingRestorationFocus()
        let restoration = ThreadRestoration(graph: graph, restorers: [adapter], focus: focus)
        let pending = Task { try await restoration.restore(id) }
        await adapter.waitUntilRequested()
        await #expect(throws: ThreadRestoreError.self) { try await restoration.restore(id) }
        pending.cancel()
        await adapter.release()
        let report = try await pending.value
        #expect(report.results.map(\.outcome) == [.cancelled, .cancelled])
        #expect(await adapter.openCount == 0)
        #expect(await adapter.checkCount == 1)
        #expect(await focus.released)
    }
}

private actor PausedCapability: ResourceRestorer {
    private var request: CheckedContinuation<RestoreCapability, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private(set) var openCount = 0
    private(set) var checkCount = 0
    func waitUntilRequested() async {
        if request != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func capability(for resource: Resource) async -> RestoreCapability {
        checkCount += 1
        return await withCheckedContinuation {
            request = $0
            observer?.resume()
            observer = nil
        }
    }
    func release() { request?.resume(returning: .resource); request = nil }
    func restore(_ resource: Resource) -> RestoreResult {
        openCount += 1
        return RestoreResult(resource: resource.id, capability: .resource, outcome: .restored)
    }
}

private actor RecordingRestorationFocus: RestorationFocus {
    private let token = UUID()
    private(set) var released = false
    func beginRestoration(_ thread: ThreadID) -> UUID { token }
    func endRestoration(_ token: UUID) { released = token == self.token }
}
