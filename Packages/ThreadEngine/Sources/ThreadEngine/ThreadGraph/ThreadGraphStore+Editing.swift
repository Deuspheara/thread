import Foundation
import ThreadDomain

extension ThreadGraphStore {
    /// Resolves UI identities against current graph metadata before applying a correction.
    @discardableResult
    func edit(_ edit: ThreadEdit, at time: Date) throws -> ResourceReassignmentRecord? {
        switch edit {
        case .split(let source, let target, let title, let resources):
            try split(source, into: target, title: title, resources: resources, at: time)
        case .merge(let source, let target): try merge(source, into: target)
        case .pin(let id, let pinned): try pin(id, pinned: pinned)
        case .rename(let id, let title): try rename(id, title: title)
        case .archive(let id, let archived): try archive(id, archived: archived)
        case .chooseApplication(let resource, let thread, let application):
            try chooseApplication(resource, in: thread, application: application)
        case .reassign(let resource, let source, let target):
            return try reassignWithEvidence(resource, from: source, to: target, at: time)
        }
        return nil
    }

    private func reassignWithEvidence(_ resource: ResourceID, from source: ThreadID, to target: ThreadID,
                                     at time: Date) throws -> ResourceReassignmentRecord {
        guard time.timeIntervalSinceReferenceDate.isFinite else { throw ThreadEditError.invalidSelection }
        guard let destination = detail(target), !destination.thread.isArchived else {
            throw ThreadEditError.invalidDestination
        }
        guard let edge = detail(source)?.resources.first(where: { $0.resource.id == resource }) else {
            throw ThreadEditError.resourceDisappeared
        }
        let record = ResourceReassignmentRecord(id: .init(rawValue: UUID()), timestamp: time,
            resourceKind: edge.resource.kind, origin: edge.userCorrected ? .explicit : .inferred,
            status: edge.status, source: source, target: target, decisionRecordID: edge.membershipRecordID)
        try reassign(ResourceEvidence(resource: edge.resource, firstSeen: edge.firstSeen,
            lastSeen: edge.lastSeen, source: edge.source), to: target)
        let existingPreference = destination.resources.first { $0.resource.id == resource }?.restoreApplication
        relationships[target]?[resource]?.restoreApplication = existingPreference?.origin == .explicit
            ? existingPreference : edge.restoreApplication
        return record
    }
}
