import Foundation
import Testing
import ThreadDomain
@testable import ThreadDecisions

struct RemoteDecisionTests {
    private let endpoint = URL(string: "https://thread.example/decisions")!
    private let context = ActivityContext(startedAt: Date(timeIntervalSince1970: 1),
        endedAt: Date(timeIntervalSince1970: 25), resources: [])

    @Test func membershipMapsOnlyOfferedAliasesAndSendsRedactedAuthenticatedEnvelope() async throws {
        let transport = ReplyTransport(target: "c0")
        let engine = try JevDecisionEngine(endpoint: endpoint, bearerToken: { "test-session-token" }, transport: transport)
        let resource = Resource.file(FileIdentity(path: "/Users/private-person/project/Session.swift"))
        let observed = ActivityContext(startedAt: context.startedAt, endedAt: context.endedAt, resources: [
            ResourceEvidence(resource: resource, firstSeen: context.startedAt, lastSeen: context.endedAt,
                source: ActivitySourceID(rawValue: "secret-source"))])
        let candidate = ScoredThreadCandidate(candidate: ThreadCandidate(id: ThreadID(rawValue: UUID()),
            title: "PRIVATE TITLE", lastActiveAt: context.endedAt, resourceIDs: [resource.id]), relevance: 0.8, signals: [.sameFile])
        #expect(try await engine.classifyMembership(context: observed, candidates: [candidate]).target == .existing(candidate.candidate.id))
        let captured = try #require(await transport.lastRequest)
        #expect(captured.url == endpoint)
        #expect(captured.httpMethod == "POST")
        #expect(captured.value(forHTTPHeaderField: "Authorization") == "Bearer test-session-token")
        let body = String(decoding: try #require(captured.httpBody), as: UTF8.self)
        for secret in ["private-person", "secret-source", "PRIVATE TITLE", candidate.candidate.id.rawValue.uuidString, "test-session-token"] {
            #expect(!body.contains(secret))
        }
        #expect(body.contains("Session.swift"))
        await transport.setTarget("c9")
        await #expect(throws: RemoteDecisionError.invalidResponse) {
            try await engine.classifyMembership(context: observed, candidates: [candidate])
        }
    }

    @Test func transitionAndPersistenceDecodeTypedOutcomesWithoutThreadIDs() async throws {
        let transport = ReplyTransport()
        let engine = try JevDecisionEngine(endpoint: endpoint, bearerToken: { "token" }, transport: transport)
        let id = ThreadID(rawValue: UUID())
        let receipt = DecisionRecordID(rawValue: UUID())
        let transition = try await engine.detectTransition(context: context, active: id,
            membership: MembershipDecision(target: .existing(id), confidence: 0.95, recordID: receipt))
        #expect(transition.shouldTransition)
        let transitionBody = String(decoding: try #require(await transport.lastRequest?.httpBody), as: UTF8.self)
        #expect(!transitionBody.contains(id.rawValue.uuidString))
        #expect(!transitionBody.contains(receipt.rawValue.uuidString) && !transitionBody.contains("recordID"))
        #expect(transitionBody.contains("targetIsActive"))
        let persistence = try await engine.classifyPersistence(resource: .file(FileIdentity(path: "/private/Project.swift")), context: context)
        #expect(persistence.disposition == .durable)
        let body = try #require(await transport.lastRequest?.httpBody)
        let decoded = try JSONDecoder().decode(CapturedEnvelope.self, from: body)
        #expect(decoded.resourceAlias == "r0")
        #expect(decoded.context.resources.first?.observedSeconds == 0)
    }

    @Test func invalidEndpointAndCredentialsNeverReachTransport() async throws {
        let transport = ReplyTransport()
        for raw in ["http://thread.example/decisions", "https://user:pass@thread.example/", "https://thread.example/?key=secret", "https://thread.example/#secret"] {
            #expect(throws: RemoteDecisionError.invalidEndpoint) {
                try JevDecisionEngine(endpoint: URL(string: raw)!, bearerToken: { "token" }, transport: transport)
            }
        }
        for token in ["", "token\r\nX-Header: injected", String(repeating: "a", count: 4097)] {
            let engine = try JevDecisionEngine(endpoint: endpoint, bearerToken: { token }, transport: transport)
            await #expect(throws: RemoteDecisionError.authenticationRequired) {
                try await engine.classifyMembership(context: context, candidates: [])
            }
        }
        #expect(await transport.calls == 0)
    }

    @Test func wrongCorrelationMalformedConfidenceAndOversizedRepliesAreRejected() async throws {
        let transport = ReplyTransport()
        let engine = try JevDecisionEngine(endpoint: endpoint, bearerToken: { "token" }, transport: transport)
        for fault in [ReplyTransport.Fault.wrongID, .wrongVersion, .wrongKind, .badConfidence, .malformed] {
            await transport.setFault(fault)
            await #expect(throws: RemoteDecisionError.invalidResponse) {
                try await engine.classifyMembership(context: context, candidates: [])
            }
        }
        await transport.setFault(.oversized)
        await #expect(throws: RemoteDecisionError.responseTooLarge) {
            try await engine.classifyMembership(context: context, candidates: [])
        }
    }

    @Test func malformedBackendReplyFallsBackWithInvalidResponseDiagnostic() async throws {
        let transport = ReplyTransport()
        await transport.setFault(.malformed)
        let remote = try JevDecisionEngine(endpoint: endpoint, bearerToken: { "token" }, transport: transport)
        let (stream, continuation) = AsyncStream<DecisionFallback>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let hybrid = HybridDecisionEngine(remote: remote, onFallback: { continuation.yield($0) })
        let decision = try await hybrid.classifyMembership(context: context, candidates: [])
        #expect(decision.target == .undetermined)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .invalidResponse)
        continuation.finish()
    }

    @Test func cancellationAndAuthenticationFailurePropagateWithoutNetwork() async throws {
        let transport = ReplyTransport()
        let cancelled = try JevDecisionEngine(endpoint: endpoint, bearerToken: { throw CancellationError() }, transport: transport)
        await #expect(throws: CancellationError.self) { try await cancelled.classifyMembership(context: context, candidates: []) }
        let unavailable = try JevDecisionEngine(endpoint: endpoint, bearerToken: { throw RemoteDecisionError.transportUnavailable }, transport: transport)
        await #expect(throws: RemoteDecisionError.authenticationRequired) {
            try await unavailable.classifyMembership(context: context, candidates: [])
        }
        #expect(await transport.calls == 0)
    }
}

private struct CapturedEnvelope: Decodable {
    struct Context: Decodable {
        struct Evidence: Decodable { let observedSeconds: Int }
        let resources: [Evidence]
    }
    let context: Context
    let requestID: UUID
    let kind: String
    let resourceAlias: String?
}

private actor ReplyTransport: DecisionHTTPTransport {
    enum Fault { case wrongID, wrongVersion, wrongKind, badConfidence, malformed, oversized }
    var lastRequest: URLRequest?
    var calls = 0
    private var target: String
    private var fault: Fault?
    init(target: String = "new") { self.target = target }
    func setTarget(_ value: String) { target = value }
    func setFault(_ value: Fault) { fault = value }
    func send(_ request: URLRequest) throws -> Data {
        lastRequest = request
        calls += 1
        let envelope = try JSONDecoder().decode(CapturedEnvelope.self, from: request.httpBody!)
        if fault == .malformed { return Data("not-json".utf8) }
        if fault == .oversized { return Data(repeating: 32, count: 65_537) }
        let id = fault == .wrongID ? UUID() : envelope.requestID
        let version = fault == .wrongVersion ? 2 : 1
        let kind = fault == .wrongKind ? "unknown" : envelope.kind
        let confidence = fault == .badConfidence ? 1.5 : 0.97
        let field: String
        switch envelope.kind {
        case "transition": field = "\"shouldTransition\":true"
        case "persistence": field = "\"disposition\":\"durable\""
        default: field = "\"target\":\"\(target)\""
        }
        return Data("{\"schemaVersion\":\(version),\"requestID\":\"\(id.uuidString)\",\"kind\":\"\(kind)\",\"confidence\":\(confidence),\(field)}".utf8)
    }
}
