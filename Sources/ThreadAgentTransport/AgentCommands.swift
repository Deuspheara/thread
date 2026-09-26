import Foundation
import ThreadDomain

/// Defines application intents; no shell command, OS object or arbitrary workflow can cross this boundary.
public enum AgentCommand: Codable, Sendable {
    case configure(debugDirectory: String?)
    case start, prepare, refreshObservation, requestPermission, shutdown
    case recent(limit: Int)
    case detail(ThreadID, after: ResourceID?, limit: Int)
    case destinations(query: String, excluding: ThreadID, limit: Int)
    case search(query: String, includeArchived: Bool, limit: Int)
    case edit(ThreadEdit), restore(ThreadID)
    case exclusions, saveExclusions(ObservationExclusions)
    case remoteState, remoteApply(RemoteInferencePreferences, token: String?), remoteDisable, remoteForget
}

public extension AgentCommand {
    /// Lost or cancelled acknowledgement for these intents must never invite automatic replay.
    var requiresCompletionAcknowledgement: Bool {
        switch self {
        case .edit, .restore, .saveExclusions, .remoteApply, .remoteDisable, .remoteForget: true
        default: false
        }
    }
}

public enum AgentFailure: Codable, Sendable {
    case unavailable, invalidRequest, busy, cancelled, completionUnknown
    case edit(ThreadEditError), read(ThreadReadError), restore(ThreadRestoreError)
    case remote(RemoteInferenceSetupError)
}

public struct AgentAvailability: Codable, Sendable {
    public let shell: Bool
    public let browser: Bool
    public let processIdentifier: Int32
    public init(shell: Bool, browser: Bool, processIdentifier: Int32) {
        self.shell = shell; self.browser = browser; self.processIdentifier = processIdentifier
    }
}

public enum AgentReplyBody: Codable, Sendable {
    case done, availability(AgentAvailability), history(HistoryStatus)
    case summaries([ThreadSummary]), detail(ThreadDetailPage?), destinations([ThreadDomain.Thread])
    case search([ThreadSearchResult]), restore(ThreadRestoreReport)
    case exclusions(ObservationExclusions), remote(RemoteInferenceState), failure(AgentFailure)
}

public enum AgentPublication: Codable, Sendable {
    case context(CurrentContext), threads(ThreadPresentation), disconnected
}
