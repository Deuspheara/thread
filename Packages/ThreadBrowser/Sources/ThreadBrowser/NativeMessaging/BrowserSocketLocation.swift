import Foundation

/// Shares the default private socket location between the app and browser host.
public enum BrowserSocketLocation {
    public static func safariURL(groupIdentifier: String) throws -> URL {
        guard !groupIdentifier.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            throw BrowserTransportError.unavailable
        }
        return container.appendingPathComponent("Browser/activity.sock")
    }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Thread/Browser/activity.sock")
    }
}
