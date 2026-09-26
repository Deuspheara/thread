import Foundation
import ThreadDomain

public enum RemoteDecisionError: Error, Equatable, Sendable {
    case invalidEndpoint, authenticationRequired, invalidRequest, invalidResponse
    case responseTooLarge, rateLimited, timedOut, transportUnavailable
}

/// Defines the versioned Thread backend envelope without exposing provider-specific types.
struct DecisionAPIRequest: Encodable, Sendable {
    enum Kind: String, Codable, Sendable { case membership, transition, persistence }
    struct Transition: Encodable, Sendable {
        let activeThreadPresent: Bool
        let targetIsActive: Bool
        let membershipConfidence: Double
    }
    let schemaVersion = 1
    let requestID: UUID
    let kind: Kind
    let context: RedactedDecisionPayload
    let transition: Transition?
    let resourceAlias: String?
}

/// Decodes normalized backend decisions before mapping them into Domain values.
struct DecisionAPIResponse: Decodable, Sendable {
    let schemaVersion: Int
    let requestID: UUID
    let kind: DecisionAPIRequest.Kind
    let confidence: Double
    let target: String?
    let shouldTransition: Bool?
    let disposition: PersistenceDisposition?

    func validate(for request: DecisionAPIRequest) throws {
        guard schemaVersion == 1, requestID == request.requestID, kind == request.kind,
              confidence.isFinite, (0...1).contains(confidence) else { throw RemoteDecisionError.invalidResponse }
        switch kind {
        case .membership:
            guard target != nil, shouldTransition == nil, disposition == nil else { throw RemoteDecisionError.invalidResponse }
        case .transition:
            guard shouldTransition != nil, target == nil, disposition == nil else { throw RemoteDecisionError.invalidResponse }
        case .persistence:
            guard disposition != nil, target == nil, shouldTransition == nil else { throw RemoteDecisionError.invalidResponse }
        }
    }
}
