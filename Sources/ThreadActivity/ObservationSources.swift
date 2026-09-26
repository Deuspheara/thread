import ThreadDomain
import ThreadMacOS
import ThreadShell
import ThreadGit
import ThreadBrowser
import OSLog

/// Owns platform observer startup and teardown without presentation models or classification.
@MainActor
final class ObservationSources {
    struct Startup {
        let events: [any ActivitySource]
        let shellAvailable: Bool
        let browserAvailable: Bool
    }

    private let workspace: WorkspaceActivitySource
    private let accessibility: AccessibilityActivitySource
    private let shell: ShellActivitySource
    private let git: GitActivitySource
    private let browser: BrowserActivitySource
    private let safari: BrowserActivitySource?
    private var gitTask: Task<Void, Never>?
    private var started = false
    private var stopped = false

    init(workspace: WorkspaceActivitySource, accessibility: AccessibilityActivitySource,
         shell: ShellActivitySource, git: GitActivitySource, browser: BrowserActivitySource, safari: BrowserActivitySource?) {
        self.workspace = workspace
        self.accessibility = accessibility
        self.shell = shell
        self.git = git
        self.browser = browser
        self.safari = safari
    }

    func start() -> Startup? {
        guard !started, !stopped else { return nil }
        started = true
        workspace.start()
        accessibility.start()
        let shellAvailable = startShell()
        var browserAvailable = startBrowser()
        var events: [any ActivitySource] = [workspace, accessibility, git, browser]
        if let safari {
            do { try safari.start(); events.append(safari) }
            catch {
                Logger(subsystem: "app.thread.desktop", category: "browser").error("Safari listener unavailable")
                browserAvailable = false
            }
        }
        gitTask = Task { [git] in await git.run() }
        return Startup(events: events, shellAvailable: shellAvailable, browserAvailable: browserAvailable)
    }

    func stop() {
        stopped = true
        workspace.stop()
        accessibility.stop()
        shell.stop()
        browser.stop()
        safari?.stop()
        gitTask?.cancel()
        gitTask = nil
    }

    func cancelPendingLookups() async { await git.cancelPendingLookups() }

    isolated deinit { stop() }

    private func startShell() -> Bool {
        do { try shell.start(); return true }
        catch {
            Logger(subsystem: "app.thread.desktop", category: "shell").error("Shell listener unavailable")
            return false
        }
    }

    private func startBrowser() -> Bool {
        do { try browser.start(); return true }
        catch {
            Logger(subsystem: "app.thread.desktop", category: "browser").error("Browser listener unavailable")
            return false
        }
    }
}
