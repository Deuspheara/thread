import AppKit
// Legacy C constants are immutable in practice but lack concurrency annotations.
@preconcurrency import ApplicationServices
import ThreadDomain

/// Reads authorization and opens the system-managed consent flow only on explicit user intent.
@MainActor
public struct AccessibilityAuthorization {
    public init() {}

    public var status: AccessibilityPermission {
        AXIsProcessTrusted() ? .granted : .notGranted
    }

    public func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func openSettings() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return false }
        return NSWorkspace.shared.open(url)
    }
}
