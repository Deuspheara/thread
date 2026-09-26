import Foundation
import Observation
import ThreadDomain

/// Presents graph details and coordinates explicit edits through the application boundary.
@MainActor @Observable
public final class ThreadDetailModel {
    public var presented = false
    public var title = ""
    public private(set) var selected: ThreadDetail?
    public private(set) var destinations: [ThreadDomain.Thread] = []
    public private(set) var busy = false
    public private(set) var message: String?
    public private(set) var loading = false
    public private(set) var totalResourceCount = 0
    public private(set) var nextResource: ResourceID?
    public var destinationQuery = "" {
        didSet {
            guard destinationQuery != oldValue else { return }
            destinationTask?.cancel()
            destinationTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(150)) }
                catch { return }
                await self?.refreshDestinations()
            }
        }
    }
    @ObservationIgnored private let reading: any ThreadReading
    @ObservationIgnored private let editing: any ThreadEditing
    public private(set) var selectedID: ThreadID?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var destinationRevision = 0
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var destinationTask: Task<Void, Never>?

    public init(editing: any ThreadEditing, reading: any ThreadReading) {
        self.editing = editing
        self.reading = reading
    }

    public func update(_ overview: ThreadPresentation) {
        guard presented else { return }
        reload()
    }

    public func open(_ id: ThreadID) {
        selectedID = id
        selected = nil
        title = ""
        message = nil
        destinationQuery = ""
        destinations = []
        revision += 1
        readTask?.cancel()
        presented = true
    }

    public func refresh() async {
        await readPage(after: nil)
        await refreshDestinations()
    }

    public func loadMore() async {
        guard !loading, let nextResource else { return }
        await readPage(after: nextResource)
    }

    public func refreshDestinations() async {
        guard let id = selectedID else { return }
        destinationRevision += 1
        let request = destinationRevision
        let query = destinationQuery
        do {
            let found = try await reading.destinations(query: query, excluding: id, limit: 20)
            guard request == destinationRevision, selectedID == id, !Task.isCancelled else { return }
            destinations = Array(found.prefix(20))
        } catch {
            guard request == destinationRevision, !Task.isCancelled else { return }
            message = "Could not load destination Threads. Retry the search."
        }
    }

    private func reload() {
        readTask?.cancel()
        readTask = Task { [weak self] in await self?.refresh() }
    }

    private func readPage(after cursor: ResourceID?) async {
        guard let id = selectedID else { return }
        revision += 1
        let request = revision
        loading = true
        defer { if request == revision { loading = false } }
        do {
            guard let page = try await reading.detailPage(id, after: cursor, limit: 64) else {
                throw ThreadReadError.unavailable
            }
            guard request == revision, selectedID == id, !Task.isCancelled else { return }
            let previous = cursor == nil ? [] : selected?.resources ?? []
            let existing = Set(previous.map { $0.resource.id })
            if selected == nil { title = page.thread.title }
            selected = ThreadDetail(thread: page.thread,
                resources: previous + page.resources.filter { !existing.contains($0.resource.id) })
            totalResourceCount = page.totalResourceCount
            nextResource = page.next
        } catch {
            guard request == revision, !Task.isCancelled else { return }
            message = "Could not load resources. Reopen this Thread to retry."
        }
    }

    isolated deinit {
        readTask?.cancel()
        destinationTask?.cancel()
    }

    public func rename() async {
        guard let id = selected?.thread.id else { return }
        await apply(.rename(id, title: title))
    }

    public func togglePin() async {
        guard let thread = selected?.thread else { return }
        await apply(.pin(thread.id, pinned: !thread.isPinned))
    }

    public func toggleArchive() async {
        guard let thread = selected?.thread else { return }
        await apply(.archive(thread.id, archived: !thread.isArchived))
    }

    func makeSplit() -> ThreadSplitModel? {
        guard let selected, !selected.thread.isArchived, selected.resources.count > 1 else { return nil }
        return ThreadSplitModel(source: selected, totalResourceCount: totalResourceCount, editing: editing)
    }

    public func merge(into target: ThreadID) async {
        guard let source = selected?.thread.id else { return }
        if await apply(.merge(source, into: target)) {
            let result = message
            open(target)
            await refresh()
            message = result
        }
    }

    public func reassign(_ resource: ResourceID, to target: ThreadID) async {
        guard let source = selected?.thread.id else { return }
        await apply(.reassign(resource, from: source, to: target))
    }

    @discardableResult
    private func apply(_ edit: ThreadEdit) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let status = try await editing.edit(edit)
            await refresh()
            message = status == .unsaved ? "Changed in memory, but not saved. Retry storage in Observed context." : "Updated."
            return true
        } catch IntentCompletionError.unknown {
            message = "Connection lost. This change may have applied. Reload the Thread before retrying."
            return false
        } catch {
            message = "Could not apply this change. Check the title, resource and destination, then retry."
            return false
        }
    }
}
