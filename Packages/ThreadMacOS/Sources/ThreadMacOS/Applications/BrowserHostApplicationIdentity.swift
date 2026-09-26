import AppKit
import Darwin
import ThreadDomain

/// Finds a supported regular browser application in the native host's same-user ancestry.
public struct BrowserHostApplicationIdentity: Sendable {
    public init() {}

    @MainActor public func resolve() -> ApplicationIdentity? {
        var pid = getppid()
        for _ in 0..<8 {
            guard pid > 1 else { return nil }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_uid == getuid() else { return nil }
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
               let identifier = app.bundleIdentifier, isSupported(identifier) {
                return ApplicationIdentity(bundleIdentifier: identifier)
            }
            let parent = Int32(info.pbi_ppid)
            guard parent != pid else { return nil }
            pid = parent
        }
        return nil
    }

    private func isSupported(_ identifier: String) -> Bool {
        let value = identifier.lowercased()
        let prefixes = ["com.google.chrome", "com.brave.browser", "com.microsoft.edgemac", "org.chromium.chromium"]
        return prefixes.contains { value == $0 || value.hasPrefix($0 + ".") }
    }
}
