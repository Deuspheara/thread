import AppKit
import ThreadDomain

/// Converts running application metadata at the adapter boundary.
enum RunningApplicationSnapshot {
    static func capture(_ application: NSRunningApplication, excluding bundleID: String) -> ApplicationContext? {
        guard let identifier = application.bundleIdentifier, identifier != bundleID,
              application.activationPolicy == .regular || application.isTerminated else { return nil }
        return ApplicationContext(
            identity: ApplicationIdentity(bundleIdentifier: identifier),
            name: application.localizedName ?? identifier,
            processIdentifier: application.processIdentifier,
            launchDate: application.launchDate
        )
    }
}
