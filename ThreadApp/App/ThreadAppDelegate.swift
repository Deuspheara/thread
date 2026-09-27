import AppKit
import ThreadMacOS
import ThreadUI
import OSLog

/// Connects process lifecycle to the observation runtime.
@MainActor
final class ThreadAppDelegate: NSObject, NSApplicationDelegate {
    private lazy var onboarding = AppComposition.makeOnboarding(
        start: { [weak self] in self?.runtime.start() },
        readPermission: { [weak self] in self?.runtime.model.context.permission ?? .unknown },
        refreshAccess: { [weak self] in self?.runtime.model.refresh() },
        requestAccess: { [weak self] in self?.runtime.model.requestPermission() })
    private lazy var welcome = OnboardingWindow(model: onboarding, showSettings: { [weak self] in self?.showSettings() })
    private lazy var settingsWindow = SettingsWindow(login: loginLaunch, exclusions: runtime.exclusions,
                                                      remote: runtime.remoteInference)
    #if DEBUG
    private var launcherPreview: LauncherPreviewFixture?
    #endif
    private var terminating = false
    let updates = AppUpdateChecks(bundle: .main)
    let loginLaunch = AppComposition.makeLoginLaunch()
    let runtime = AppComposition.makeObservation()
    private lazy var panel = SwitcherPanel(model: runtime.switcher, detail: runtime.switcherDetail, restoration: runtime.restoration)
    private var shortcut: SwitcherShortcut?

    func showSwitcher() {
        #if DEBUG
        if let launcherPreview { launcherPreview.show(); return }
        #endif
        if onboarding.hasStarted { panel.toggle() } else { showOnboarding() }
    }

    func showOnboarding() { welcome.present() }
    func showSettings() { settingsWindow.present() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AgentProbeLaunch.runIfRequested() { return }
        #if DEBUG
        if let preview = LauncherPreviewFixture.makeIfRequested() {
            launcherPreview = preview
            preview.show()
            return
        }
        if AgentCredentialFixture.runIfRequested() { return }
        if AgentFileRestoreFixture.runIfRequested() { return }
        if AgentRuntimeFixture.runIfRequested() { return }
        #endif
        if onboarding.hasStarted { runtime.start() } else { showOnboarding() }
        let shortcut = SwitcherShortcut { [weak self] in self?.showSwitcher() }
        do { try shortcut.start(); self.shortcut = shortcut }
        catch {
            runtime.switcher.shortcutUnavailable = true
            Logger(subsystem: "app.thread.desktop", category: "permissions").error("Switcher shortcut registration unavailable")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows visible: Bool) -> Bool {
        #if DEBUG
        if let launcherPreview { launcherPreview.show(); return false }
        #endif
        if !visible {
            if onboarding.hasStarted { panel.show() } else { showOnboarding() }
            return false
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        shortcut?.stop()
        panel.close()
        Task {
            await runtime.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.stop()
    }
}
