import Foundation
import ThreadDomain

/// Keeps recent resource evidence in deterministic recency order with explicit invalidation.
struct ActivityEvidenceWindow: Sendable {
    private(set) var entries: [ResourceEvidence] = []

    mutating func record(_ resources: [Resource], source: ActivitySourceID, at time: Date, limit: Int) {
        for resource in resources {
            let first = entries.first { $0.resource.id == resource.id }?.firstSeen ?? time
            entries.removeAll { $0.resource.id == resource.id }
            entries.append(ResourceEvidence(resource: resource, firstSeen: first, lastSeen: time, source: source))
        }
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    mutating func expire(before time: Date) { entries.removeAll { $0.lastSeen < time } }
    mutating func clear() { entries.removeAll(keepingCapacity: true) }

    mutating func invalidate(for event: ActivityEventKind) {
        switch event {
        case .terminalDirectoryChanged, .terminalCommandCompleted:
            entries.removeAll { $0.resource.kind == .repository || $0.resource.kind == .branch }
        case .terminalSessionEnded(let session):
            entries.removeAll { $0.resource.id == .terminal(session) }
        case .browserFocusCleared(let connection), .browserDisconnected(let connection):
            entries.removeAll {
                if case .browserPage(let tab) = $0.resource { return tab.identity.connection == connection }
                return false
            }
        case .browserTabClosed(let identity):
            entries.removeAll {
                if case .browserPage(let tab) = $0.resource { return tab.identity == identity }
                return false
            }
        case .windowClosed(let identity, _):
            entries.removeAll { $0.resource.id == .window(identity) }
        case .accessibilityPermissionChanged(let permission) where permission != .granted:
            entries.removeAll { $0.resource.kind == .window || $0.resource.kind == .file }
        default: break
        }
    }
}
