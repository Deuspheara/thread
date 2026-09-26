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
        let sender = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/ThreadShellSend").path
        let hook = resources.appendingPathComponent("thread.zsh").path
        let shellSetup = "export THREAD_SHELL_SENDER=" + shellQuote(sender) + "\nsource " + shellQuote(hook)
        return OnboardingModel(complete: complete, shellSetup: shellSetup, remember: { try completion.complete() }, start: start,
            readPermission: readPermission, refreshAccess: refreshAccess, requestAccess: requestAccess,
            openSettings: { authorization.openSettings() }, openGuide: { NSWorkspace.shared.open(resources.appendingPathComponent("Setup.md")) })
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
