import Foundation
import ThreadDomain

/// Obtains Jev decisions through an authenticated Thread backend using redacted payloads only.
public struct JevDecisionEngine: DecisionEngine {
    private let endpoint: URL
    private let bearerToken: @Sendable () async throws -> String
    private let transport: any DecisionHTTPTransport

    public init(endpoint: URL, bearerToken: @escaping @Sendable () async throws -> String) throws {
        try self.init(endpoint: endpoint, bearerToken: bearerToken, transport: URLSessionDecisionTransport())
    }

    init(endpoint: URL, bearerToken: @escaping @Sendable () async throws -> String,
         transport: any DecisionHTTPTransport) throws {
        guard let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil,
              components.fragment == nil else { throw RemoteDecisionError.invalidEndpoint }
        self.endpoint = endpoint
        self.bearerToken = bearerToken
        self.transport = transport
    }

    public func classifyMembership(context: ActivityContext, candidates: [ScoredThreadCandidate]) async throws -> MembershipDecision {
        let prepared = prepare(context, candidates: candidates)
        let request = envelope(.membership, prepared: prepared)
        let response = try await send(request)
        let target: MembershipTarget
        switch response.target {
        case "new": target = .newThread
        case "undetermined": target = .undetermined
        case .some(let alias):
            guard let id = prepared.candidateIDs[alias] else { throw RemoteDecisionError.invalidResponse }
            target = .existing(id)
        case nil: throw RemoteDecisionError.invalidResponse
        }
        return MembershipDecision(target: target, confidence: response.confidence)
    }

    public func detectTransition(context: ActivityContext, active: ThreadID?, membership: MembershipDecision) async throws -> TransitionDecision {
        guard case .existing(let target) = membership.target else {
            return TransitionDecision(shouldTransition: false, confidence: 0)
        }
        guard membership.confidence.isFinite, (0...1).contains(membership.confidence) else { throw RemoteDecisionError.invalidRequest }
        let request = envelope(.transition, prepared: prepare(context), transition: .init(
            activeThreadPresent: active != nil, targetIsActive: active == target, membershipConfidence: membership.confidence))
        let response = try await send(request)
        guard let shouldTransition = response.shouldTransition else { throw RemoteDecisionError.invalidResponse }
        return TransitionDecision(shouldTransition: shouldTransition, confidence: response.confidence)
    }

    public func classifyPersistence(resource: Resource, context: ActivityContext) async throws -> PersistenceDecision {
        let evidence = context.resources.first { $0.resource.id == resource.id } ?? ResourceEvidence(resource: resource,
            firstSeen: context.endedAt, lastSeen: context.endedAt, source: ActivitySourceID(rawValue: "decision"))
        let focused = ActivityContext(startedAt: context.startedAt, endedAt: context.endedAt,
            resources: [evidence] + context.resources.filter { $0.resource.id != resource.id })
        let request = envelope(.persistence, prepared: prepare(focused), resourceAlias: "r0")
        let response = try await send(request)
        guard let disposition = response.disposition else { throw RemoteDecisionError.invalidResponse }
        return PersistenceDecision(disposition: disposition, confidence: response.confidence)
    }

    private func prepare(_ context: ActivityContext, candidates: [ScoredThreadCandidate] = []) -> PreparedDecisionPayload {
        PrivacyRedactor().redact(DecisionPayloadBuilder().build(context: context, candidates: candidates))
    }

    private func envelope(_ kind: DecisionAPIRequest.Kind, prepared: PreparedDecisionPayload,
                          transition: DecisionAPIRequest.Transition? = nil, resourceAlias: String? = nil) -> DecisionAPIRequest {
        DecisionAPIRequest(requestID: UUID(), kind: kind, context: prepared.payload,
            transition: transition, resourceAlias: resourceAlias)
    }

    private func send(_ envelope: DecisionAPIRequest) async throws -> DecisionAPIResponse {
        try Task.checkCancellation()
        let token = try await credential()
        try Task.checkCancellation()
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(envelope)
        guard let body = request.httpBody, body.count <= 65_536 else { throw RemoteDecisionError.invalidRequest }
        let data = try await transport.send(request)
        try Task.checkCancellation()
        guard data.count <= 65_536 else { throw RemoteDecisionError.responseTooLarge }
        let response: DecisionAPIResponse
        do { response = try JSONDecoder().decode(DecisionAPIResponse.self, from: data) }
        catch { throw RemoteDecisionError.invalidResponse }
        try response.validate(for: envelope)
        return response
    }

    private func credential() async throws -> String {
        let token: String
        do { token = try await bearerToken() }
        catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            throw RemoteDecisionError.authenticationRequired
        }
        let alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~+/="
        guard !token.isEmpty, token.utf8.count <= 4096,
              token.unicodeScalars.allSatisfy({ alphabet.unicodeScalars.contains($0) }) else {
            throw RemoteDecisionError.authenticationRequired
        }
        return token
    }
}
