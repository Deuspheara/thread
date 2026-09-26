import AppKit
import ThreadDomain

/// Excludes browser titles until an extension can explicitly exclude private browsing.
@MainActor
final class WindowTitlePolicy {
    private var decisions: [ApplicationIdentity: Bool] = [:]
    private let knownBrowserPrefixes = [
        "com.apple.Safari", "com.google.Chrome", "org.chromium.Chromium", "org.mozilla.firefox",
        "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser", "app.zen-browser.zen", "org.torproject.torbrowser"
    ]

    func permitsTitle(for application: ApplicationContext) -> Bool {
        if let cached = decisions[application.identity] { return cached }
        let permitted = resolve(application)
        if decisions.count >= 256 { decisions.removeAll(keepingCapacity: true) }
        decisions[application.identity] = permitted
        return permitted
    }

    private func resolve(_ application: ApplicationContext) -> Bool {
        let bundleID = application.identity.bundleIdentifier
        if knownBrowserPrefixes.contains(where: { bundleID.hasPrefix($0) }) { return false }
        guard let url = NSRunningApplication(processIdentifier: application.processIdentifier)?.bundleURL,
              let bundle = Bundle(url: url), let info = bundle.infoDictionary else { return false }
        let types = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        return !schemes.contains { ["http", "https"].contains($0.lowercased()) }
    }
}
