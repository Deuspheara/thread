import Foundation
import ThreadDomain

/// Validates a proper resource subset and prepares explicit correction edges before graph mutation.
struct ThreadSplitPlan {
    let thread: ThreadDomain.Thread
    let resources: [ResourceID: ThreadResource]

    init(source: ThreadDetail, destination: ThreadID, title: String, selection: Set<ResourceID>, at time: Date) throws {
        guard !source.thread.isArchived, source.thread.id != destination else { throw ThreadEditError.invalidDestination }
        let existing = Set(source.resources.map { $0.resource.id })
        guard !selection.isEmpty, selection.count < existing.count else { throw ThreadEditError.invalidSelection }
        guard selection.isSubset(of: existing) else { throw ThreadEditError.resourceDisappeared }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 160 else { throw ThreadGraphError.invalidTitle }
        guard time.timeIntervalSinceReferenceDate.isFinite else { throw ThreadEditError.invalidSelection }
        thread = ThreadDomain.Thread(id: destination, title: title, createdAt: time, lastActiveAt: time)
        var moved: [ResourceID: ThreadResource] = [:]
        for var edge in source.resources where selection.contains(edge.resource.id) {
            edge.userCorrected = true
            edge.membershipRecordID = nil
            edge.confidence = 1
            edge.status = .confirmed
            edge.persistence = .durable
            moved[edge.resource.id] = edge
        }
        resources = moved
    }
}
