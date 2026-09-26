import Foundation

public enum ActivityFailure: String, Codable, Sendable { case inferenceUnavailable, backlogOverflow, clockUnavailable }

public enum HistoryStatus: String, Codable, Sendable { case sessionOnly, loading, saved, unavailable, unsaved }

/// Publishes complete engine state to the application runtime; UI uses bounded ThreadPresentation.
public struct ThreadOverview: Equatable, Sendable {
    public let threads: [ThreadDetail]
    public let active: ThreadID?
    public let history: HistoryStatus
    public let failure: ActivityFailure?
    public init(threads: [ThreadDetail], active: ThreadID?, failure: ActivityFailure? = nil, history: HistoryStatus = .sessionOnly) {
        self.history = history
        self.threads = threads
        self.active = active
        self.failure = failure
    }
}
