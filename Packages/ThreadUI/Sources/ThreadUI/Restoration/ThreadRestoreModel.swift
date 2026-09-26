import Observation
import ThreadDomain

/// Presents restoration progress and explicit partial/failure outcomes.
@MainActor @Observable
public final class ThreadRestoreModel {
    public private(set) var busy = false
    public private(set) var message: String?
    @ObservationIgnored private let restoring: any ThreadRestoring

    public init(restoring: any ThreadRestoring) { self.restoring = restoring }

    public func restore(_ id: ThreadID) async {
        guard !busy else { return }
        busy = true
        message = "Restoring…"
        defer { busy = false }
        do {
            let report = try await restoring.restore(id)
            let restored = report.results.filter { $0.outcome == .restored }.count
            let partial = report.results.filter { $0.outcome == .restored && $0.capability == .partial }.count
            let unavailable = report.results.filter { $0.outcome == .unavailable }.count
            let failed = report.results.filter { $0.outcome == .failed || $0.outcome == .cancelled }.count
            message = "Restored \(restored) (\(partial) partially) · Unavailable \(unavailable) · Failed or cancelled \(failed)"
        } catch IntentCompletionError.unknown {
            message = "Connection lost. Restoration may have started. Check your applications before retrying."
        } catch {
            message = "Restoration could not start. Try again."
        }
    }
}
