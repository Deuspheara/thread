import Foundation
import ThreadDomain

/// Restores confirmed graph resources through independent capability-based adapters.
public actor ThreadRestoration: ThreadRestoring {
    private let plan: RestorePlan
    private let graph: ThreadGraphStore
    private let restorers: [any ResourceRestorer]
    private var busy = false
    private let focus: (any RestorationFocus)?

    public init(graph: ThreadGraphStore, restorers: [any ResourceRestorer], focus: (any RestorationFocus)? = nil,
                directoryIdentity: @escaping @Sendable (String) -> String = {
                    URL(fileURLWithPath: $0).standardizedFileURL.path
                }) {
        plan = RestorePlan(directoryIdentity: directoryIdentity)
        self.graph = graph; self.restorers = restorers; self.focus = focus
    }

    public func restore(_ thread: ThreadID) async throws -> ThreadRestoreReport {
        guard !busy else { throw ThreadRestoreError.busy }
        busy = true
        defer { busy = false }
        guard await graph.detail(thread) != nil else { throw ThreadRestoreError.unknownThread }
        try Task.checkCancellation()
        let token = try await focus?.beginRestoration(thread)
        guard let detail = await graph.detail(thread) else {
            if let token { try await focus?.endRestoration(token) }
            throw ThreadRestoreError.unknownThread
        }
        var results: [RestoreResult] = []
        for resource in plan.resources(detail) {
            results.append(await restoreResource(resource))
        }
        if let token { try await focus?.endRestoration(token) }
        return ThreadRestoreReport(thread: thread, results: results)
    }

    private func restoreResource(_ resource: Resource) async -> RestoreResult {
        if Task.isCancelled { return RestoreResult(resource: resource.id, capability: .unavailable, outcome: .cancelled) }
        for restorer in restorers {
            let capability = await restorer.capability(for: resource)
            if Task.isCancelled { return RestoreResult(resource: resource.id, capability: capability, outcome: .cancelled) }
            guard capability != .unavailable else { continue }
            do {
                try Task.checkCancellation()
                return try await restorer.restore(resource)
            }
            catch is CancellationError { return RestoreResult(resource: resource.id, capability: capability, outcome: .cancelled) }
            catch { return RestoreResult(resource: resource.id, capability: capability, outcome: .failed) }
        }
        return RestoreResult(resource: resource.id, capability: .unavailable, outcome: .unavailable)
    }
}
