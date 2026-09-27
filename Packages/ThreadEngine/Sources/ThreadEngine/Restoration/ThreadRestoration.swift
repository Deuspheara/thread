import Foundation
import ThreadDomain

/// Restores confirmed graph resources through independent capability-based adapters.
public actor ThreadRestoration: ThreadRestoring {
    private let graph: ThreadGraphStore
    private let restorers: [any ResourceRestorer]
    private var busy = false
    private let focus: (any RestorationFocus)?

    public init(graph: ThreadGraphStore, restorers: [any ResourceRestorer], focus: (any RestorationFocus)? = nil) {
        self.graph = graph; self.restorers = restorers; self.focus = focus
    }

    public func restore(_ thread: ThreadID) async throws -> ThreadRestoreReport {
        guard !busy else { throw ThreadRestoreError.busy }
        busy = true
        defer { busy = false }
        guard await graph.detail(thread) != nil else { throw ThreadRestoreError.unknownThread }
        try Task.checkCancellation()
        let token = try await focus?.beginRestoration(thread)
        let plan: ThreadResumePlan
        do {
            guard let found = try await graph.resumePlan(thread) else { throw ThreadRestoreError.unknownThread }
            plan = found
        } catch {
            if let token { try await focus?.endRestoration(token) }
            throw error
        }
        var results: [RestoreResult] = []
        for resource in plan.targets {
            results.append(await restoreResource(resource))
        }
        if let token { try await focus?.endRestoration(token) }
        return ThreadRestoreReport(thread: thread, results: results)
    }

    private func restoreResource(_ target: RestoreTarget) async -> RestoreResult {
        let resource = target.resource
        if Task.isCancelled { return RestoreResult(resource: resource.id, capability: .unavailable, outcome: .cancelled) }
        for restorer in restorers {
            let capability = await restorer.capability(for: target)
            if Task.isCancelled { return RestoreResult(resource: resource.id, capability: capability, outcome: .cancelled) }
            guard capability != .unavailable else { continue }
            do {
                try Task.checkCancellation()
                return try await restorer.restore(target)
            }
            catch is CancellationError { return RestoreResult(resource: resource.id, capability: capability, outcome: .cancelled) }
            catch { return RestoreResult(resource: resource.id, capability: capability, outcome: .unknown,
                application: target.application, explanation: "Completion could not be verified. This operation may have started. Check the application before retrying; Thread did not retry it.") }
        }
        return RestoreResult(resource: resource.id, capability: .unavailable, outcome: .unavailable,
            application: target.application, explanation: target.application == nil
                ? "No available integration for this item." : "Preferred application or item is unavailable. Choose an installed application in Details.")
    }
}
