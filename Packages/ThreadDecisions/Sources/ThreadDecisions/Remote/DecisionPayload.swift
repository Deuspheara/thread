import Foundation
import ThreadDomain

/// Holds narrow local inputs that deliberately cannot be serialized for transport.
struct DecisionPayloadDraft: Sendable {
    struct Evidence: Sendable {
        let id: ResourceID
        let kind: ResourceKind
        let value: String?
        let seconds: Double
    }
    struct Candidate: Sendable {
        let id: ThreadID
        let relevance: Double
        let signals: [CandidateSignal]
        let matchingResources: [Int]
        let secondsSinceActive: Double
    }
    let seconds: Double
    let resources: [Evidence]
    let candidates: [Candidate]
}

/// Represents the only allowlisted context shape intended for remote encoding.
struct RedactedDecisionPayload: Encodable, Sendable {
    struct Evidence: Encodable, Sendable {
        let alias: String
        let kind: ResourceKind
        let label: String?
        let observedSeconds: Int
    }
    struct Candidate: Encodable, Sendable {
        let alias: String
        let relevance: Double
        let signals: [CandidateSignal]
        let matchingResources: [String]
        let secondsSinceActive: Int
    }
    let schemaVersion: Int
    let observedSeconds: Int
    let resources: [Evidence]
    let candidates: [Candidate]
}

/// Keeps response aliases mapped to local identities outside the encoded payload.
struct PreparedDecisionPayload: Sendable {
    let payload: RedactedDecisionPayload
    let candidateIDs: [String: ThreadID]
}
