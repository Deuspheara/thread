import Foundation
import Observation
import ThreadDomain

/// Presents accepted requests, per-item limitations and uncertain completion without retrying operations.
@MainActor @Observable
public final class ThreadRestoreModel {
    public struct Item: Identifiable {
        public let result: RestoreResult
        public let title: String
        public let application: String
        public var id: ResourceID { result.resource }
        public var status: String {
            switch result.outcome {
            case .unavailable: "Unavailable"
            case .failed: "Failed"
            case .unknown: "Completion unverified"
            case .cancelled: "Cancelled"
            case .restored: result.capability == .partial ? "Partially restored" : "Request accepted"
            }
        }
        public var explanation: String {
            result.explanation ?? (result.outcome == .restored
                ? result.capability == .partial ? "Only supported parts were requested. Processes, commands and editor state are not restored."
                    : "The integration accepted the request; full document or window state is not verified."
                : "Check the application, permissions and item before retrying in Thread.")
        }
    }
    public private(set) var busy = false
    public private(set) var message: String?
    public private(set) var items: [Item] = []
    public private(set) var thread: ThreadID?
    public var showingOutcomes = false
    @ObservationIgnored private let restoring: any ThreadRestoring
    public init(restoring: any ThreadRestoring) { self.restoring = restoring }
    public func restore(_ id: ThreadID, title: String = "Thread", plan: ThreadResumePlan? = nil) async {
        guard !busy else { return }
        busy = true
        thread = id
        items = []
        message = "Resuming \(title)…"
        defer { busy = false }
        do {
            let report = try await restoring.restore(id)
            items = report.results.map { result in
                let target = plan?.targets.first { $0.resource.id == result.resource }
                let resource = target?.resource
                return Item(result: result, title: resource.map { ResourceLabel().title($0) } ?? ResourceLabel().title(result.resource),
                    application: result.application?.name ?? target.map { ThreadResumePlan.application(for: $0).name } ?? "")
            }
            let issues = report.results.filter { $0.outcome != .restored || $0.capability == .partial }.count
            if report.results.isEmpty { message = "No confirmed items to resume" }
            else if issues == 0 { message = "\(title) resumed" }
            else if report.results.allSatisfy({ $0.outcome != .restored }) { message = "Couldn’t confirm resume · \(issues) \(issues == 1 ? "issue" : "issues")" }
            else { message = "\(title) resumed · \(issues) \(issues == 1 ? "issue" : "issues")" }
        } catch IntentCompletionError.unknown {
            message = "Connection lost. Resume may have started. Check applications before retrying."
        } catch {
            message = "Couldn’t resume \(title). Reopen Thread and try again."
        }
    }
}
