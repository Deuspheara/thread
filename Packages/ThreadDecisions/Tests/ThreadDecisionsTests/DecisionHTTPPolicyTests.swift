import Foundation
import Testing
@testable import ThreadDecisions

struct DecisionHTTPPolicyTests {
    @Test func responsePolicyRejectsAuthRateLimitRedirectsAndUnsafeBodies() throws {
        let url = URL(string: "https://thread.example/decisions")!
        for (status, expected) in [(401, RemoteDecisionError.authenticationRequired), (403, .authenticationRequired),
                                  (429, .rateLimited), (503, .transportUnavailable), (302, .invalidResponse)] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            #expect(throws: expected) { try DecisionHTTPResponsePolicy.validate(response) }
        }
        let oversized = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json", "Content-Length": "65537"])!
        #expect(throws: RemoteDecisionError.responseTooLarge) { try DecisionHTTPResponsePolicy.validate(oversized) }
        let html = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!
        #expect(throws: RemoteDecisionError.invalidResponse) { try DecisionHTTPResponsePolicy.validate(html) }
        let json = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json; charset=utf-8"])!
        try DecisionHTTPResponsePolicy.validate(json)
    }

    @Test func redirectCannotForwardAuthenticationOrPayload() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = URL(string: "https://thread.example/decisions")!
        let response = HTTPURLResponse(url: original, statusCode: 307, httpVersion: nil, headerFields: nil)!
        let destination = URLRequest(url: URL(string: "https://other.example/")!)
        let result = await DecisionRedirectRejection().urlSession(session, task: session.dataTask(with: original),
            willPerformHTTPRedirection: response, newRequest: destination)
        #expect(result == nil)
    }
}
