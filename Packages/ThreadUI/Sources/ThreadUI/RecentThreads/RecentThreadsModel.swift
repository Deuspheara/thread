import Foundation
import Observation
import ThreadDomain

/// Presents inferred work without exposing classification or graph implementations to views.
@MainActor @Observable
public final class RecentThreadsModel {
    public struct Row: Identifiable {
        public let id: ThreadID
        public let title: String
        public let lastActive: Date
        public let resourceCount: Int
        public let isPinned: Bool
        public let isActive: Bool
    }
    public private(set) var rows: [Row] = []
    public private(set) var history: HistoryStatus = .loading
    public private(set) var unavailable = false
    public init() {}

    public func update(_ overview: ThreadPresentation) {
        rows = overview.threads.filter { !$0.thread.isArchived }.prefix(8).map {
            Row(id: $0.thread.id, title: $0.thread.title, lastActive: $0.thread.lastActiveAt,
                resourceCount: $0.resourceCount,
                isPinned: $0.thread.isPinned, isActive: $0.thread.id == overview.active)
        }
        unavailable = overview.failure != nil
        history = overview.history
    }
}
