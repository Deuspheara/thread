#if DEBUG
import AppKit
import Foundation
import ThreadDomain
import ThreadUI

/// Hosts the real launcher with fictional metadata and no observers, helper, storage or app launches.
@MainActor
final class LauncherPreviewFixture {
    private let panel: SwitcherPanel
    private init() {
        let data = LauncherPreviewData()
        let switcher = SwitcherModel(search: data, reading: data)
        switcher.update(ThreadPresentation(threads: data.summaries, active: data.initial.first?.thread.id, history: .sessionOnly))
        panel = SwitcherPanel(model: switcher, detail: ThreadDetailModel(editing: data, reading: data),
                              restoration: ThreadRestoreModel(restoring: data))
    }
    static func makeIfRequested() -> LauncherPreviewFixture? {
        guard ProcessInfo.processInfo.environment["THREAD_LAUNCHER_PREVIEW"] == "1"
            || Bundle.main.object(forInfoDictionaryKey: "ThreadLauncherPreview") as? Bool == true else { return nil }
        let appearance = ProcessInfo.processInfo.environment["THREAD_LAUNCHER_APPEARANCE"]
            ?? Bundle.main.object(forInfoDictionaryKey: "ThreadLauncherPreviewAppearance") as? String
        NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        return LauncherPreviewFixture()
    }
    func show() { panel.show() }
}

/// Supplies bounded synthetic metadata through the same UI ports used by the helper client.
private actor LauncherPreviewData: ThreadReading, ThreadSearch, ThreadEditing, ThreadRestoring {
    nonisolated let initial: [ThreadDetail]
    nonisolated var summaries: [ThreadSummary] {
        initial.map { ThreadSummary(thread: $0.thread, resourceCount: $0.resources.count,
            applications: ThreadWorkSummary($0).applications.map(\.name), work: ThreadWorkSummary($0)) }
    }
    private var details: [ThreadDetail]
    init() {
        let now = Date()
        let zed = ApplicationContext(identity: ApplicationIdentity(bundleIdentifier: "dev.zed.Zed"), name: "Zed", processIdentifier: 0)
        let brave = ApplicationIdentity(bundleIdentifier: "com.brave.Browser")
        let preferences = RestoreApplication(identity: zed.identity, name: "Zed", origin: .observed)
        func edge(_ resource: Resource, app: RestoreApplication? = nil) -> ThreadResource {
            ThreadResource(resource: resource, confidence: 1, firstSeen: now, lastSeen: now,
                source: ActivitySourceID(rawValue: "preview"), status: .confirmed, restoreApplication: app)
        }
        func thread(_ title: String, minutes: Double, resources: [ThreadResource]) -> ThreadDetail {
            let time = now.addingTimeInterval(-minutes * 60)
            return ThreadDetail(thread: ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: title,
                createdAt: time, lastActiveAt: time), resources: resources)
        }
        func page(_ title: String, url: String) -> Resource {
            .browserPage(BrowserTabContext(identity: BrowserTabIdentity(connection: .init(rawValue: UUID()), tab: 1),
                browser: .brave, window: 1, url: url, domain: "example.com", title: title, isActive: true, application: brave))
        }
        let project = "/fixture/homecontrol-app"
        let terminal = TerminalContext(session: .init(rawValue: UUID()), processIdentifier: 0, workingDirectory: project,
            terminalApplication: "Apple_Terminal", sequence: 1)
        let resources = [edge(.application(zed)),
            edge(.file(FileIdentity(path: project)), app: preferences),
            edge(.file(FileIdentity(path: project + "/lib/ota/ota_controller.dart")), app: preferences),
            edge(.file(FileIdentity(path: project + "/lib/ota/reconnect_view.dart")), app: preferences),
            edge(page("GitHub · PR #418 — Fix OTA reconnect", url: "https://example.com/pull/418")),
            edge(page("Matter OTA documentation", url: "https://example.com/matter/ota")),
            edge(.terminal(terminal)), edge(.workingDirectory(project)),
            edge(.branch(RepositoryIdentity(commonDirectory: project + "/.git"), "feature/ota-reconnect"))]
        initial = [thread("HomeControl · OTA reconnect", minutes: 0, resources: resources),
            thread("Thread · launcher polish", minutes: 12, resources: [edge(.file(FileIdentity(path: "/fixture/thread/README.md")), app: preferences)]),
            thread("Weekend reading", minutes: 95, resources: [edge(page("Native macOS interface notes", url: "https://example.com/notes"))])]
        details = initial
    }
    func recentSummaries(limit: Int) -> [ThreadSummary] { Array(summaries.prefix(limit)) }
    func detailPage(_ id: ThreadID, after resource: ResourceID?, limit: Int) -> ThreadDetailPage? {
        guard let detail = details.first(where: { $0.thread.id == id }) else { return nil }
        let start = resource.flatMap { id in detail.resources.firstIndex { $0.resource.id == id } }.map { $0 + 1 } ?? 0
        let items = Array(detail.resources.dropFirst(start).prefix(limit))
        return ThreadDetailPage(thread: detail.thread, resources: items, totalResourceCount: detail.resources.count,
            next: start + items.count < detail.resources.count ? items.last?.resource.id : nil)
    }
    func destinations(query: String, excluding thread: ThreadID, limit: Int) -> [ThreadDomain.Thread] {
        Array(details.map(\.thread).filter { $0.id != thread && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }.prefix(limit))
    }
    func search(query: String, includeArchived: Bool, limit: Int) -> [ThreadSearchResult] {
        Array(details.filter { $0.thread.title.localizedCaseInsensitiveContains(query) }.prefix(limit).map {
            ThreadSearchResult(id: $0.thread.id, title: $0.thread.title, lastActiveAt: $0.thread.lastActiveAt,
                resourceCount: $0.resources.count, isArchived: $0.thread.isArchived)
        })
    }
    func edit(_ edit: ThreadEdit) throws -> HistoryStatus { throw ThreadEditError.unavailable }
    func restore(_ id: ThreadID) throws -> ThreadRestoreReport {
        guard let detail = details.first(where: { $0.thread.id == id }) else { throw ThreadRestoreError.unknownThread }
        return ThreadRestoreReport(thread: id, results: ThreadResumePlan(detail).targets.map {
            RestoreResult(resource: $0.resource.id, capability: .unavailable, outcome: .unavailable,
                application: $0.application, explanation: "Synthetic preview: no application was opened.")
        })
    }
}
#endif
