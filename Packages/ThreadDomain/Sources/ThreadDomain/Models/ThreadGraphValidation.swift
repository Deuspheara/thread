import Foundation

public enum ThreadGraphValidationError: Error, Sendable { case invalidState }

/// Checks graph invariants before persistence or restoration can replace authoritative state.
public enum ThreadGraphValidation {
    public static func validate(_ state: ThreadGraphState) throws {
        let ids = Set(state.threads.map { $0.thread.id })
        guard ids.count == state.threads.count else { throw ThreadGraphValidationError.invalidState }
        var corrections: [ResourceID: ThreadID] = [:]
        for correction in state.corrections {
            guard ids.contains(correction.thread), corrections[correction.resource] == nil else { throw ThreadGraphValidationError.invalidState }
            corrections[correction.resource] = correction.thread
        }
        for detail in state.threads {
            guard !detail.thread.title.isEmpty, detail.thread.title.count <= 160,
                  detail.thread.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  detail.thread.lastActiveAt.timeIntervalSinceReferenceDate.isFinite,
                  detail.thread.createdAt <= detail.thread.lastActiveAt,
                  Set(detail.resources.map { $0.resource.id }).count == detail.resources.count else { throw ThreadGraphValidationError.invalidState }
            for edge in detail.resources {
                guard edge.persistence == .durable, edge.confidence.isFinite, (0...1).contains(edge.confidence),
                      edge.firstSeen.timeIntervalSinceReferenceDate.isFinite, edge.lastSeen.timeIntervalSinceReferenceDate.isFinite,
                      edge.firstSeen <= edge.lastSeen else { throw ThreadGraphValidationError.invalidState }
                if let app = edge.restoreApplication {
                    guard edge.resource.kind == .file, app.isValid, app.origin != .fallback else { throw ThreadGraphValidationError.invalidState }
                }
                if edge.userCorrected {
                    guard corrections[edge.resource.id] == detail.thread.id, edge.status == .confirmed,
                          edge.confidence == 1, edge.membershipRecordID == nil else {
                        throw ThreadGraphValidationError.invalidState
                    }
                }
                if let owner = corrections[edge.resource.id], owner != detail.thread.id { throw ThreadGraphValidationError.invalidState }
            }
        }
        for correction in state.corrections {
            guard state.threads.contains(where: { $0.thread.id == correction.thread && $0.resources.contains {
                $0.resource.id == correction.resource && $0.userCorrected
            } }) else { throw ThreadGraphValidationError.invalidState }
        }
    }
}
