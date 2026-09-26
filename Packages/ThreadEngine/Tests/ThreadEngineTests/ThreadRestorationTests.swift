import Foundation
import Testing
import ThreadDomain
@testable import ThreadEngine

struct ThreadRestorationTests {
    @Test func directoryRepresentationsOpenOnlyOnce() {
        let time = Date(timeIntervalSince1970: 100)
        let terminal = Resource.terminal(TerminalContext(session: TerminalSessionIdentity(rawValue: UUID()), processIdentifier: 42,
            workingDirectory: "/work/project", terminalApplication: "Apple_Terminal", sequence: 1))
        let resources = [Resource.workingDirectory("/work/project/"), terminal].map {
            ThreadResource(resource: $0, confidence: 1, firstSeen: time, lastSeen: time,
                           source: ActivitySourceID(rawValue: "test"), status: .confirmed)
        }
        let detail = ThreadDetail(thread: ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: "Work", createdAt: time, lastActiveAt: time), resources: resources)
        #expect(RestorePlan().resources(detail) == [terminal])
    }

    @Test func directoryAliasesUseInjectedIdentityAndPreserveTheSelectedResource() {
        let time = Date(timeIntervalSince1970: 100)
        let terminal = Resource.terminal(TerminalContext(session: TerminalSessionIdentity(rawValue: UUID()), processIdentifier: 42,
            workingDirectory: "/private/tmp/fixture", terminalApplication: "Apple_Terminal", sequence: 1))
        let other = Resource.workingDirectory("/different/fixture")
        let edges = [Resource.workingDirectory("/tmp/fixture"), terminal, other].map {
            ThreadResource(resource: $0, confidence: 1, firstSeen: time, lastSeen: time,
                source: ActivitySourceID(rawValue: "test"), status: .confirmed)
        }
        let detail = ThreadDetail(thread: ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: "Work",
            createdAt: time, lastActiveAt: time), resources: edges)
        let plan = RestorePlan(directoryIdentity: { $0 == "/tmp/fixture" ? "/private/tmp/fixture" : $0 })
        #expect(plan.resources(detail) == [terminal, other])
    }

    @Test func failureDoesNotStopOtherResourcesAndProvisionalEdgesAreExcluded() async throws {
        let graph = ThreadGraphStore()
        let id = ThreadID(rawValue: UUID())
        let time = Date(timeIntervalSince1970: 100)
        func edge(_ path: String, _ status: MembershipStatus = .confirmed) -> ThreadResource {
            ThreadResource(resource: .file(FileIdentity(path: path)), confidence: 0.98,
                           firstSeen: time, lastSeen: time, source: ActivitySourceID(rawValue: "test"), status: status)
        }
        try await graph.restore(ThreadGraphState(threads: [ThreadDetail(
            thread: ThreadDomain.Thread(id: id, title: "Restore", createdAt: time, lastActiveAt: time),
            resources: [edge("/a-failed"), edge("/b-restored"), edge("/c-unavailable"), edge("/d-provisional", .provisional)])], corrections: []))
        let adapter = RecordingRestorer()
        let restoration = ThreadRestoration(graph: graph, restorers: [adapter])
        let report = try await restoration.restore(id)
        #expect(report.results.map(\.outcome) == [.failed, .restored, .unavailable])
        #expect(await adapter.paths == ["/a-failed", "/b-restored"])
        await #expect(throws: ThreadRestoreError.self) { try await restoration.restore(ThreadID(rawValue: UUID())) }
    }
}

private actor RecordingRestorer: ResourceRestorer {
    enum Failure: Error { case unavailable }
    private(set) var paths: [String] = []
    func capability(for resource: Resource) -> RestoreCapability {
        guard case .file(let file) = resource, file.path != "/c-unavailable" else { return .unavailable }
        return .resource
    }
    func restore(_ resource: Resource) throws -> RestoreResult {
        guard case .file(let file) = resource else { throw Failure.unavailable }
        paths.append(file.path)
        if file.path == "/a-failed" { throw Failure.unavailable }
        return RestoreResult(resource: resource.id, capability: .resource, outcome: .restored)
    }
}
