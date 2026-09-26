import Foundation
import Observation
import ThreadDomain

/// Presents recent and searched Threads with stable keyboard selection.
@MainActor @Observable
public final class SwitcherModel {
    public struct Row: Identifiable {
        public let id: ThreadID
        public let isPinned: Bool
        public let isArchived: Bool
        public let title: String
        public let lastActive: Date
        public let resourceCount: Int
        public let applications: String
    }
    public var shortcutUnavailable = false
    public var query = ""
    public var includeArchived = false
    public var selection: ThreadID?
    public private(set) var rows: [Row] = []
    public private(set) var loading = false
    public private(set) var failed = false
    @ObservationIgnored private var recent: [Row] = []
    @ObservationIgnored private let search: any ThreadSearch
    @ObservationIgnored private var revision = 0

    public init(search: any ThreadSearch) { self.search = search }

    public func update(_ overview: ThreadPresentation) {
        recent = overview.threads.filter { !$0.thread.isArchived }.map { detail in
            let names = detail.applications.joined(separator: " · ")
            return Row(id: detail.thread.id, isPinned: detail.thread.isPinned, isArchived: false, title: detail.thread.title, lastActive: detail.thread.lastActiveAt,
                       resourceCount: detail.resourceCount, applications: names)
        }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { display(Array(recent.prefix(20))) }
    }

    public func reset() {
        revision += 1
        query = ""
        includeArchived = false
        loading = false
        failed = false
        selection = nil
        display(Array(recent.prefix(20)))
    }

    public func refresh() async {
        revision += 1
        let request = revision
        let archived = includeArchived
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        failed = false
        guard !text.isEmpty else { loading = false; display(Array(recent.prefix(20))); return }
        loading = true
        display([])
        do {
            try await Task.sleep(for: .milliseconds(150))
            let found = try await search.search(query: text, includeArchived: archived, limit: 30)
            guard request == revision, !Task.isCancelled else { return }
            display(found.map { result in
                Row(id: result.id, isPinned: recent.first { $0.id == result.id }?.isPinned ?? false, isArchived: result.isArchived, title: result.title, lastActive: result.lastActiveAt, resourceCount: result.resourceCount,
                    applications: recent.first { $0.id == result.id }?.applications ?? "")
            })
            loading = false
        } catch {
            guard request == revision else { return }
            loading = false
            failed = !Task.isCancelled
        }
    }

    public func move(_ offset: Int) {
        guard !rows.isEmpty else { return }
        let index = selection.flatMap { id in rows.firstIndex { $0.id == id } } ?? 0
        selection = rows[min(rows.count - 1, max(0, index + offset))].id
    }

    private func display(_ rows: [Row]) {
        self.rows = rows
        if !rows.contains(where: { $0.id == selection }) { selection = rows.first?.id }
    }
}
