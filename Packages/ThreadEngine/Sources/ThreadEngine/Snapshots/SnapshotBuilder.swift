import Foundation
import ThreadDomain

/// Builds bounded restore candidates from confirmed relationships, preferring pinned/recent resources.
public struct SnapshotBuilder: Sendable {
    private let maximumResources: Int
    private let makeID: @Sendable () -> ThreadSnapshotID
    public init(maximumResources: Int = 128, makeID: @escaping @Sendable () -> ThreadSnapshotID = { ThreadSnapshotID(rawValue: UUID()) }) {
        precondition((1...512).contains(maximumResources))
        self.maximumResources = maximumResources
        self.makeID = makeID
    }
    public func build(_ detail: ThreadDetail, at time: Date) -> ThreadSnapshot? {
        let selected = detail.resources.enumerated().filter { $0.element.status == .confirmed && $0.element.persistence == .durable }.sorted {
            if $0.element.pinned != $1.element.pinned { return $0.element.pinned }
            if $0.element.lastSeen != $1.element.lastSeen { return $0.element.lastSeen > $1.element.lastSeen }
            return $0.offset < $1.offset
        }.prefix(maximumResources).map(\.element)
        guard !selected.isEmpty else { return nil }
        return ThreadSnapshot(id: makeID(), thread: detail.thread.id, capturedAt: time, title: detail.thread.title, resources: selected)
    }
}
