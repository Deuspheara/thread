import Foundation
import Testing
import ThreadDomain
@testable import ThreadEngine

struct ApplicationTargetTests {
    let time = Date(timeIntervalSince1970: 100)
    let file = FileIdentity(path: "/fixture/project/main.swift")
    func context(_ bundle: String, at offset: Double = 0) -> ActivityContext {
        let app = ApplicationContext(identity: ApplicationIdentity(bundleIdentifier: bundle), name: bundle, processIdentifier: 1)
        let window = WindowContext(identity: WindowIdentity(rawValue: UUID()), application: app, title: "main.swift", frame: nil, document: file)
        let date = time.addingTimeInterval(offset)
        return ActivityContext(startedAt: date, endedAt: date, resources: [Resource.file(file), .window(window), .application(app)].map {
            ResourceEvidence(resource: $0, firstSeen: date, lastSeen: date, source: ActivitySourceID(rawValue: "fixture"))
        })
    }
    @Test func sameFileRetainsDifferentThreadAppsAndCorrectionOutranksNewEvidence() async throws {
        let graph = ThreadGraphStore()
        let a = try #require(await graph.apply(.automatic(.newThread), confidence: 1, context: context("dev.zed.Zed")))
        let b = try #require(await graph.apply(.automatic(.newThread), confidence: 1, context: context("com.microsoft.VSCode", at: 1)))
        #expect(await graph.detail(a)?.resources.first { $0.resource.id == .file(file) }?.restoreApplication?.identity.bundleIdentifier == "dev.zed.Zed")
        #expect(await graph.detail(b)?.resources.first { $0.resource.id == .file(file) }?.restoreApplication?.identity.bundleIdentifier == "com.microsoft.VSCode")
        let correction = RestoreApplication(identity: ApplicationIdentity(bundleIdentifier: "dev.zed.Zed"), name: "Zed", origin: .explicit)
        try await graph.chooseApplication(.file(file), in: b, application: correction)
        _ = try await graph.apply(.automatic(.existing(b)), confidence: 1, context: context("com.microsoft.VSCode", at: 2))
        #expect(await graph.detail(b)?.resources.first { $0.resource.id == .file(file) }?.restoreApplication == correction)
        _ = try await graph.apply(.automatic(.existing(b)), confidence: 1, context: context("com.microsoft.VSCode", at: 3), persistence: [.file(file): .discard])
        #expect(await graph.detail(b)?.resources.first { $0.resource.id == .file(file) }?.restoreApplication == correction)
        let restored = ThreadGraphStore()
        let saved = await graph.checkpoint()
        try await restored.restore(saved)
        #expect(await restored.detail(b)?.resources.first { $0.resource.id == .file(file) }?.restoreApplication == correction)
    }
    @Test func discardedWindowMetadataStillSuppliesObservedFileApplication() async throws {
        let graph = ThreadGraphStore()
        let observed = context("dev.zed.Zed")
        let window = try #require(observed.resources.first { $0.resource.kind == .window })
        let id = try #require(await graph.apply(.automatic(.newThread), confidence: 1, context: observed,
            persistence: [window.resource.id: .discard]))
        #expect(await graph.detail(id)?.resources.first { $0.resource.id == .file(file) }?.restoreApplication?.identity.bundleIdentifier == "dev.zed.Zed")
    }
    @Test func planDeduplicatesDocumentAppAndWindowAndPreviewMatchesExecution() async throws {
        let graph = ThreadGraphStore()
        let id = try #require(await graph.apply(.automatic(.newThread), confidence: 1, context: context("dev.zed.Zed")))
        let detail = try #require(await graph.detail(id))
        let plan = ThreadResumePlan(detail)
        #expect(plan.targets.count == 1)
        #expect(plan.targets.first?.resource.id == .file(file))
        #expect(plan.groups.first?.application.identity?.bundleIdentifier == "dev.zed.Zed")
        let recorder = TargetRecorder()
        let restoration = ThreadRestoration(graph: graph, restorers: [recorder])
        _ = try await restoration.restore(id)
        #expect(await recorder.targets == plan.targets)
    }
    @Test func helperDetailPlanAndExecutionShareDirectoryAliasDeduplication() async throws {
        let graph = ThreadGraphStore(resumeDirectoryIdentity: { $0 == "/tmp/fixture" ? "/private/tmp/fixture" : $0 })
        let date = time
        let resources = [Resource.workingDirectory("/tmp/fixture"), .workingDirectory("/private/tmp/fixture")]
        let context = ActivityContext(startedAt: date, endedAt: date, resources: resources.map {
            ResourceEvidence(resource: $0, firstSeen: date, lastSeen: date, source: ActivitySourceID(rawValue: "fixture"))
        })
        let id = try #require(await graph.apply(.automatic(.newThread), confidence: 1, context: context))
        let reading: any ThreadReading = graph
        let preview = try #require(await reading.resumePlan(id))
        #expect(preview.targets.count == 1)
        let page = try #require(await graph.detailPage(id, after: nil, limit: 64))
        #expect(page.resumePlan == preview)
        let recorder = TargetRecorder()
        _ = try await ThreadRestoration(graph: graph, restorers: [recorder]).restore(id)
        #expect(await recorder.targets == preview.targets)
    }
    @Test func legacyRelationshipsDecodeWithoutInventingOwnership() throws {
        let edge = ThreadResource(resource: .file(file), confidence: 1, firstSeen: time, lastSeen: time,
            source: ActivitySourceID(rawValue: "fixture"), status: .confirmed)
        let data = try JSONEncoder().encode(edge)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "restoreApplication")
        let legacy = try JSONDecoder().decode(ThreadResource.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.restoreApplication == nil)
    }
    @Test func workspaceFallbackNeverOverridesAnExplicitEditor() {
        let preference = RestoreApplication(identity: ApplicationIdentity(bundleIdentifier: "dev.zed.Zed"), name: "Zed", origin: .explicit)
        let edge = ThreadResource(resource: .file(FileIdentity(path: "/fixture/work.code-workspace")), confidence: 1,
            firstSeen: time, lastSeen: time, source: ActivitySourceID(rawValue: "fixture"), status: .confirmed, restoreApplication: preference)
        let thread = ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: "Work", createdAt: time, lastActiveAt: time)
        #expect(ThreadResumePlan(ThreadDetail(thread: thread, resources: [edge])).targets.first?.application == preference)
    }
}

private actor TargetRecorder: ResourceRestorer {
    private(set) var targets: [RestoreTarget] = []
    func capability(for resource: Resource) -> RestoreCapability { .unavailable }
    func restore(_ resource: Resource) -> RestoreResult { RestoreResult(resource: resource.id, capability: .unavailable, outcome: .unavailable) }
    func capability(for target: RestoreTarget) -> RestoreCapability { .resource }
    func restore(_ target: RestoreTarget) -> RestoreResult {
        targets.append(target)
        return RestoreResult(resource: target.resource.id, capability: .resource, outcome: .restored, application: target.application)
    }
}
