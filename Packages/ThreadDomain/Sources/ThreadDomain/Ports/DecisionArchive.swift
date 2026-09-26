import Foundation

/// Persists bounded inference results for local evaluation without retaining model inputs.
public protocol DecisionArchive: Sendable {
    func append(decisions: [DecisionRecord], at time: Date, retention: DecisionRetentionPolicy) async throws
    func decisions(since time: Date, limit: Int) async throws -> [DecisionRecord]
}
