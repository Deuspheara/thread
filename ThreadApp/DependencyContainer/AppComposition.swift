import Foundation
import ThreadDomain
import ThreadMacOS
import ThreadUI

/// Constructs UI models around the helper's application-facing command ports.
@MainActor
enum AppComposition {
    static func makeObservation() -> ObservationRuntime {
        #if DEBUG
        let debugDirectory = ProcessInfo.processInfo.environment["THREAD_DATA_DIRECTORY"]
        #else
        let debugDirectory: String? = nil
        #endif
        let client = AgentClient(app: Bundle.main.bundleURL, debugDirectory: debugDirectory)
        let authorization = AccessibilityAuthorization()
        let model = CurrentContextModel(prepareStorage: { try await client.prepare() },
            refreshObservation: { Task {
                do { try await client.refresh() }
                catch { LogCategory.activity.logger.error("Observation refresh unavailable") }
            } }, requestAuthorization: { Task {
                do { try await client.requestPermission() }
                catch { LogCategory.permissions.logger.error("Permission request unavailable") }
            } }, openAuthorizationSettings: { authorization.openSettings() })
        let exclusions = ObservationExclusionsModel(initial: nil,
            load: { try await client.exclusions() }, save: { try await client.saveExclusions($0) })
        let remote = RemoteInferenceModel(load: { try await client.remoteState() },
            save: { try await client.remoteApply($0, token: $1) }, disable: { try await client.remoteDisable() },
            forget: { try await client.remoteForget() })
        return ObservationRuntime(model: model, exclusions: exclusions, remoteInference: remote,
            restoration: ThreadRestoreModel(restoring: client), switcher: SwitcherModel(search: client),
            search: ThreadSearchModel(search: client), activity: client)
    }

    static func makeLoginLaunch() -> LoginLaunchModel {
        let registration = LoginLaunchRegistration()
        return LoginLaunchModel(readStatus: { registration.status },
                                change: { try registration.setEnabled($0) },
                                showSettings: { registration.openSettings() })
    }

    static func storageDirectory() -> URL {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["THREAD_DATA_DIRECTORY"], path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return URL.applicationSupportDirectory.appendingPathComponent("Thread", isDirectory: true)
    }

}
