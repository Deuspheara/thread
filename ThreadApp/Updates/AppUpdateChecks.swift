import Foundation
import Observation
import OSLog
import Sparkle

/// Starts Sparkle only for an explicit update check in a configured application bundle.
@MainActor @Observable
final class AppUpdateChecks {
    private(set) var canCheck: Bool
    private(set) var message: String?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var availability: NSKeyValueObservation?

    init(bundle: Bundle) {
        canCheck = UpdateConfiguration(feed: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) != nil
        message = canCheck ? nil : "Updates unavailable for this build."
    }

    func check() {
        guard canCheck else { return }
        if controller == nil {
            let instance = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
            instance.updater.automaticallyChecksForUpdates = false
            instance.updater.automaticallyDownloadsUpdates = false
            instance.updater.sendsSystemProfile = false
            do { try instance.updater.start() }
            catch {
                canCheck = false
                message = "Could not start update checking."
                Logger(subsystem: "app.thread.desktop", category: "updates").error("Update initialization unavailable")
                return
            }
            controller = instance
            availability = instance.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
                let available = change.newValue ?? false
                Task { @MainActor in self?.canCheck = available }
            }
        }
        guard controller?.updater.canCheckForUpdates == true else { return }
        controller?.checkForUpdates(nil)
    }
}
