import Foundation
import ThreadDomain
import ThreadUI

/// Connects current-context and Thread publications to the app presentation for its lifetime.
@MainActor
final class ObservationRuntime {
    let exclusions: ObservationExclusionsModel
    let remoteInference: RemoteInferenceModel
    let model: CurrentContextModel
    let threads = RecentThreadsModel()
    let restoration: ThreadRestoreModel
    let switcher: SwitcherModel
    let search: ThreadSearchModel
    let detail: ThreadDetailModel
    let switcherDetail: ThreadDetailModel
    private let activity: AgentClient
    private var threadsTask: Task<Void, Never>?
    private var presentationTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?

    init(model: CurrentContextModel, exclusions: ObservationExclusionsModel, remoteInference: RemoteInferenceModel, restoration: ThreadRestoreModel, switcher: SwitcherModel, search: ThreadSearchModel, activity: AgentClient) {
        self.exclusions = exclusions
        self.remoteInference = remoteInference
        self.activity = activity
        self.restoration = restoration
        self.switcher = switcher
        detail = ThreadDetailModel(editing: activity, reading: activity)
        switcherDetail = ThreadDetailModel(editing: activity, reading: activity)
        self.model = model
        self.search = search
    }

    func start() {
        guard presentationTask == nil else { return }
        presentationTask = Task { [activity, model] in
            for await context in activity.contexts() {
                guard !Task.isCancelled else { return }
                model.update(context)
            }
        }
        threadsTask = Task { [activity, threads, model, detail, switcher, switcherDetail] in
            var previousCount = -1
            for await overview in activity.updates() {
                guard !Task.isCancelled else { return }
                if overview.threads.count != previousCount {
                    LogCategory.classification.logger.info("Inferred Thread count: \(overview.threads.count)")
                    previousCount = overview.threads.count
                }
                threads.update(overview)
                detail.update(overview)
                switcherDetail.update(overview)
                switcher.update(overview)
                model.updateHistoryStatus(overview.history)
            }
        }
        startupTask = Task { [activity, model, exclusions] in
            do {
                let startup = try await activity.start()
                #if DEBUG
                if let path = ProcessInfo.processInfo.environment["THREAD_DATA_DIRECTORY"] {
                    let marker = URL(fileURLWithPath: path).appendingPathComponent("AgentRuntimePID")
                    try Data(String(startup.processIdentifier).utf8).write(to: marker, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
                }
                #endif
                model.setShellAvailable(startup.shell)
                model.setBrowserAvailable(startup.browser)
                await model.prepare()
                await exclusions.reload()
            } catch {
                model.setShellAvailable(false)
                model.setBrowserAvailable(false)
                model.updateHistoryStatus(.unavailable)
                LogCategory.activity.logger.error("Background activity startup unavailable")
            }
        }
    }

    func shutdown() async {
        stop()
        await activity.shutdown()
    }

    isolated deinit { stop() }

    func stop() {
        threadsTask?.cancel()
        threadsTask = nil
        startupTask?.cancel()
        presentationTask?.cancel()
        startupTask = nil
        presentationTask = nil
    }
}
