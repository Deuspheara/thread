import Foundation

/// Carries recent work metadata without graph relationships or resource identities.
public struct ThreadSummary: Equatable, Codable, Sendable {
    public let thread: Thread
    public let resourceCount: Int
    public let applications: [String]
    public let work: ThreadWorkSummary?
    public init(thread: Thread, resourceCount: Int, applications: [String], work: ThreadWorkSummary? = nil) {
        self.thread = thread
        self.resourceCount = resourceCount
        self.applications = applications
        self.work = work
    }
}

/// Publishes bounded recent summaries and runtime status; details are read separately.
public struct ThreadPresentation: Codable, Sendable {
    public let threads: [ThreadSummary]
    public let active: ThreadID?
    public let history: HistoryStatus
    public let failure: ActivityFailure?
    public init(threads: [ThreadSummary], active: ThreadID?, failure: ActivityFailure? = nil, history: HistoryStatus = .sessionOnly) {
        self.threads = threads
        self.active = active
        self.history = history
        self.failure = failure
    }
}
