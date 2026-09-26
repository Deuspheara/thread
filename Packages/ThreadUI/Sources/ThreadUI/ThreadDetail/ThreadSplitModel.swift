import Foundation
import Observation
import ThreadDomain

/// Presents a resource selection and submits one explicit split correction.
@MainActor
@Observable
final class ThreadSplitModel: Identifiable {
    let id = ThreadID(rawValue: UUID())
    let source: ThreadDetail
    private let totalResourceCount: Int
    var title = ""
    var selection: Set<ResourceID> = []
    private(set) var busy = false
    private(set) var complete = false
    private(set) var message: String?
    private let editing: any ThreadEditing

    init(source: ThreadDetail, totalResourceCount: Int, editing: any ThreadEditing) { self.source = source; self.totalResourceCount = totalResourceCount; self.editing = editing }

    var canSplit: Bool {
        !complete && !source.thread.isArchived && !selection.isEmpty && selection.count < totalResourceCount
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 160
    }

    func select(_ resource: ResourceID, included: Bool) {
        if included { selection.insert(resource) } else { selection.remove(resource) }
    }

    func save() async {
        guard !busy, canSplit else { return }
        busy = true
        defer { busy = false }
        do {
            let status = try await editing.edit(.split(source.thread.id, into: id, title: title, resources: selection))
            complete = true
            message = status == .unsaved ? "Created in memory, but not saved. Retry storage in Observed context." : "Thread created."
        } catch IntentCompletionError.unknown {
            message = "Connection lost. The split may have applied. Check recent Threads before retrying."
        } catch {
            message = "Could not split this Thread. Check the selected resources and title, then retry."
        }
    }
}
