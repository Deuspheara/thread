import Foundation
import ThreadDomain

/// Serializes explicit graph edits and restoration focus boundaries with inference work.
enum ActivityUserCommand: Sendable {
    case edit(ThreadEdit)
    case beginRestoration(UUID, ThreadID)
    case endRestoration(UUID)
}
