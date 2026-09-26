import Foundation

/// Shares the default private socket location between the app and shell sender.
public enum ShellSocketLocation {
    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Thread/Shell/activity.sock")
    }
}
