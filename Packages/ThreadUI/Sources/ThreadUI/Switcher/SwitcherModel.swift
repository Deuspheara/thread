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
        public let work: ThreadWorkSummary?
    }
    public var shortcutUnavailable = false
    public var focusRequest = 0
    public var query = ""
    public var includeArchived = false
    public var selection: ThreadID?
    public private(set) var rows: [Row] = []
    public private(set) var loading = false
    public private(set) var failed = false
    public private(set) var active: ThreadID?
    public private(set) var previewRevision = 0
    public private(set) var preview: ThreadResumePlan?
    public private(set) var previewLoading = false
    public private(set) var previewUnavailable = false
    @ObservationIgnored private let reading: (any ThreadReading)?
    @ObservationIgnored private var recent: [Row] = []
    @ObservationIgnored private let search: any ThreadSearch
    @ObservationIgnored private var revision = 0

    public init(search: any ThreadSearch, reading: (any ThreadReading)? = nil) { self.search = search; self.reading = reading }

    public func update(_ overview: ThreadPresentation) {
        let selectedBefore = recent.first { $0.id == selection }
        active = overview.active
        recent = overview.threads.filter { !$0.thread.isArchived }.map { detail in
            let names = detail.applications.joined(separator: " · ")
            return Row(id: detail.thread.id, isPinned: detail.thread.isPinned, isArchived: false, title: detail.thread.title, lastActive: detail.thread.lastActiveAt,
                       resourceCount: detail.resourceCount, applications: names, work: detail.work)
        }
        let selectedAfter = recent.first { $0.id == selection }
        if selectedBefore?.resourceCount != selectedAfter?.resourceCount || selectedBefore?.work != selectedAfter?.work {
            previewRevision += 1
        }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { display(Array(recent.prefix(20))) }
    }

    public func reset() {
        revision += 1
        previewRevision += 1
        previewLoading = false
        previewUnavailable = false
        query = ""
        includeArchived = false
        loading = false
        failed = false
        selection = nil
        display(Array(recent.prefix(20)))
        if rows.contains(where: { $0.id == active }) { selection = active }
        preview = nil
    }

    public func refresh() async {
        revision += 1
        let request = revision
        let archived = includeArchived
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        failed = false
        guard !text.isEmpty else { loading = false; display(Array(recent.prefix(20))); return }
        loading = true
        do {
            try await Task.sleep(for: .milliseconds(150))
            let found = try await search.search(query: text, includeArchived: archived, limit: 30)
            guard request == revision, !Task.isCancelled else { return }
            display(found.map { result in
                Row(id: result.id, isPinned: recent.first { $0.id == result.id }?.isPinned ?? false, isArchived: result.isArchived, title: result.title, lastActive: result.lastActiveAt, resourceCount: result.resourceCount,
                    applications: recent.first { $0.id == result.id }?.applications ?? "", work: recent.first { $0.id == result.id }?.work)
            })
            loading = false
        } catch {
            guard request == revision else { return }
            loading = false
            failed = !Task.isCancelled
        }
    }

    public func loadPreview() async {
        let id = selection
        let request = previewRevision
        preview = nil
        previewUnavailable = false
        previewLoading = false
        guard let id, let reading else { return }
        previewLoading = true
        defer { if selection == id, previewRevision == request { previewLoading = false } }
        do {
            let plan = try await reading.resumePlan(id)
            guard selection == id, previewRevision == request, !Task.isCancelled else { return }
            preview = plan
            previewUnavailable = plan == nil
        } catch {
            guard selection == id, previewRevision == request, !Task.isCancelled else { return }
            previewUnavailable = true
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
