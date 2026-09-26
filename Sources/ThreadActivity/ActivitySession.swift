import Foundation
import ThreadDomain

/// Exposes the helper-owned runtime and concrete application intents without UI models.
@MainActor
public final class ActivitySession {
    public let runtime: ActivityRuntime
    public let search: any ThreadSearch
    public let restoration: any ThreadRestoring
    public let remote: RemoteInferenceSetup
    private let loadRules: @MainActor () throws -> ObservationExclusions
    private let saveRules: @MainActor (ObservationExclusions) async throws -> Void
    private let refreshSources: @MainActor () -> Void
    private let requestAccess: @MainActor () -> Void

    init(runtime: ActivityRuntime, search: any ThreadSearch, restoration: any ThreadRestoring,
         remote: RemoteInferenceSetup, loadExclusions: @escaping @MainActor () throws -> ObservationExclusions,
         saveExclusions: @escaping @MainActor (ObservationExclusions) async throws -> Void,
         refresh: @escaping @MainActor () -> Void, requestPermission: @escaping @MainActor () -> Void) {
        self.runtime = runtime
        self.search = search
        self.restoration = restoration
        self.remote = remote
        loadRules = loadExclusions
        saveRules = saveExclusions
        refreshSources = refresh
        requestAccess = requestPermission
    }

    public func exclusions() throws -> ObservationExclusions { try loadRules() }
    public func saveExclusions(_ value: ObservationExclusions) async throws { try await saveRules(value) }
    public func refreshObservation() { refreshSources() }
    public func requestPermission() { requestAccess() }
}
