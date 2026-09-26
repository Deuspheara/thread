import Foundation

/// Brackets user-requested restoration so generated observations cannot become inferred user intent.
public protocol RestorationFocus: Sendable {
    func beginRestoration(_ thread: ThreadID) async throws -> UUID
    func endRestoration(_ token: UUID) async throws
}
