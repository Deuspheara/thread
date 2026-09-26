import OSLog

/// Defines the application's stable logging categories without retaining mutable logging state.
enum LogCategory: String {
    case activity, classification, browser, shell, git, persistence, restore, permissions

    var logger: Logger {
        Logger(subsystem: "app.thread.desktop", category: rawValue)
    }
}
