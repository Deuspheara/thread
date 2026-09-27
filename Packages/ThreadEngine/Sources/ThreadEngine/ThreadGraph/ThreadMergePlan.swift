import Foundation
import ThreadDomain

/// Resolves a resource union before a merge mutates actor-owned graph state.
struct ThreadMergePlan {
    let source: ThreadDomain.Thread
    let destination: ThreadDomain.Thread
    let resources: [ResourceID: ThreadResource]

    init(source: ThreadDetail, destination: ThreadDetail) throws {
        guard source.thread.id != destination.thread.id, !source.thread.isArchived, !destination.thread.isArchived
        else { throw ThreadEditError.invalidDestination }
        var archived = source.thread
        archived.isArchived = true
        var target = destination.thread
        target.lastActiveAt = max(target.lastActiveAt, source.thread.lastActiveAt)
        target.isPinned = target.isPinned || source.thread.isPinned
        var resources = Dictionary(uniqueKeysWithValues: destination.resources.map { ($0.resource.id, $0) })
        for var incoming in source.resources {
            // A user merge moves source ownership; no inference assigned this edge to the destination.
            incoming.membershipRecordID = nil
            if let existing = resources[incoming.resource.id] {
                resources[incoming.resource.id] = Self.combine(existing, incoming)
            } else { resources[incoming.resource.id] = incoming }
        }
        self.source = archived
        self.destination = target
        self.resources = resources
    }

    private static func combine(_ existing: ThreadResource, _ incoming: ThreadResource) -> ThreadResource {
        let latest: ThreadResource
        if existing.status != incoming.status { latest = existing.status == .confirmed ? existing : incoming }
        else { latest = incoming.lastSeen > existing.lastSeen ? incoming : existing }
        let corrected = existing.userCorrected || incoming.userCorrected
        let confirmed = existing.status == .confirmed || incoming.status == .confirmed
        let confidence = corrected ? 1 : max(existing.status == .confirmed ? existing.confidence : 0,
                                            incoming.status == .confirmed ? incoming.confidence : 0)
        let persistence: PersistenceDisposition = existing.persistence == .durable || incoming.persistence == .durable ? .durable : .sessionOnly
        return ThreadResource(resource: latest.resource, confidence: confirmed ? confidence : max(existing.confidence, incoming.confidence),
                              firstSeen: min(existing.firstSeen, incoming.firstSeen), lastSeen: max(existing.lastSeen, incoming.lastSeen),
                              source: latest.source, status: corrected || confirmed ? .confirmed : .provisional,
                              pinned: existing.pinned || incoming.pinned, userCorrected: corrected, persistence: persistence,
                              restoreApplication: existing.restoreApplication?.origin == .explicit ? existing.restoreApplication
                                : incoming.restoreApplication?.origin == .explicit ? incoming.restoreApplication
                                : latest.restoreApplication)
    }
}
