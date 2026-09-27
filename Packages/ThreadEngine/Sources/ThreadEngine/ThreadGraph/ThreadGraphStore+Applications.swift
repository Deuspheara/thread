import Foundation
import ThreadDomain

extension ThreadGraphStore {
    /// Retains only document ownership witnessed in the same accepted observation as the file.
    func retainObservedApplication(_ evidence: ResourceEvidence, in context: ActivityContext, thread: ThreadID) {
        guard evidence.resource.kind == .file,
              relationships[thread]?[evidence.resource.id]?.restoreApplication?.origin != .explicit else { return }
        let matches = context.resources.compactMap { candidate -> ApplicationContext? in
            guard candidate.lastSeen == evidence.lastSeen, candidate.source == evidence.source,
                  case .window(let window) = candidate.resource, let document = window.document,
                  Resource.file(document).id == evidence.resource.id else { return nil }
            return window.application
        }
        guard let app = matches.first, Set(matches.map(\.identity)).count == 1 else { return }
        let preference = RestoreApplication(identity: app.identity, name: app.name, origin: .observed)
        guard preference.isValid else { return }
        relationships[thread]?[evidence.resource.id]?.restoreApplication = preference
    }

    /// Persists a document application correction without making file membership exclusive across Threads.
    public func chooseApplication(_ resource: ResourceID, in thread: ThreadID, application: RestoreApplication) throws {
        guard application.isValid, application.origin == .explicit else { throw ThreadEditError.invalidSelection }
        guard let detail = detail(thread), !detail.thread.isArchived else { throw ThreadEditError.invalidDestination }
        guard let edge = relationships[thread]?[resource], edge.resource.kind == .file else {
            throw ThreadEditError.resourceDisappeared
        }
        relationships[thread]?[resource]?.restoreApplication = application
        relationships[thread]?[resource]?.persistence = .durable
        relationships[thread]?[resource]?.status = .confirmed
    }
}
