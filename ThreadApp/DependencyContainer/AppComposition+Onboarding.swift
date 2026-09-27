import AppKit
import Foundation
import OSLog
import ThreadDomain
import ThreadMacOS
import ThreadPersistence
import ThreadUI

extension AppComposition {
    static func makeOnboarding(start: @escaping @MainActor () -> Void,
                               readPermission: @escaping @MainActor () -> AccessibilityPermission,
                               refreshAccess: @escaping @MainActor () -> Void,
                               requestAccess: @escaping @MainActor () -> Void) -> OnboardingModel {
        let completion = OnboardingCompletionFile(directory: storageDirectory())
        var complete = false
        do { complete = try completion.isComplete() }
        catch { Logger(subsystem: "app.thread.desktop", category: "settings").error("Setup completion unavailable") }
        #if DEBUG
        if ProcessInfo.processInfo.environment["THREAD_SKIP_ONBOARDING"] == "1",
           ProcessInfo.processInfo.environment["THREAD_DATA_DIRECTORY"]?.hasPrefix("/") == true { complete = true }
        #endif
        let authorization = AccessibilityAuthorization()
        let resources = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
        return OnboardingModel(complete: complete, remember: { try completion.complete() }, start: start,
            readPermission: readPermission, refreshAccess: refreshAccess, requestAccess: requestAccess,
            openSettings: { authorization.openSettings() }, openGuide: { NSWorkspace.shared.open(resources.appendingPathComponent("Setup.md")) })
    }
}
