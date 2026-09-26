import Foundation
import ThreadDomain

struct ClassifiedActivityResources: Sendable {
    let context: ActivityContext
    let persistence: [ResourceID: PersistenceDisposition]
}

/// Classifies bounded distinct resources before graph mutation, preserving cancellation atomicity.
struct ResourcePersistenceClassifier: Sendable {
    let policy = ResourcePersistencePolicy()
    func classify(_ context: ActivityContext, decisions: any DecisionEngine) async throws -> ClassifiedActivityResources {
        var persistence: [ResourceID: PersistenceDisposition] = [:]
        var resources: [ResourceEvidence] = []
        for evidence in context.resources {
            guard persistence[evidence.resource.id] == nil else { continue }
            try Task.checkCancellation()
            let decision = try await decisions.classifyPersistence(resource: evidence.resource, context: context)
            try Task.checkCancellation()
            persistence[evidence.resource.id] = policy.authorize(decision)
            resources.append(evidence)
            if resources.count == 128 { break }
        }
        return ClassifiedActivityResources(context: ActivityContext(startedAt: context.startedAt,
            endedAt: context.endedAt, resources: resources), persistence: persistence)
    }
}
