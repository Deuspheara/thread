import Foundation
import ThreadDomain

/// Batches accepted observations with explicit time; an owning actor schedules nextDeadline.
public struct EventAggregator: Sendable {
    private let policy: AggregationPolicy
    private var reducer = CurrentContextReducer()
    private var evidence = ActivityEvidenceWindow()
    private var batchStart: Date?
    private var lastChange: Date?
    private var logicalTime = Date.distantPast
    private var recentIDs: [ActivityEventID] = []
    private var sourceTimes: [ActivitySourceID: Date] = [:]
    private var repositoryAnchor: RepositoryContext?

    public init(policy: AggregationPolicy = AggregationPolicy()) { self.policy = policy }

    public mutating func discardEvidence() {
        evidence.clear()
        batchStart = nil
        lastChange = nil
        repositoryAnchor = nil
    }

    /// Keeps ordering and permission state current without classifying programmatic restoration events.
    public mutating func observeWithoutEvidence(_ event: ActivityEvent, at time: Date) {
        guard time >= logicalTime, !recentIDs.contains(event.id),
              event.timestamp >= sourceTimes[event.source, default: .distantPast] else { return }
        logicalTime = time
        remember(event)
        reducer.apply(event)
        discardEvidence()
    }

    public var nextDeadline: Date? {
        guard let batchStart, let lastChange else { return nil }
        return min(lastChange.addingTimeInterval(policy.quietInterval),
                   batchStart.addingTimeInterval(policy.maximumBatchInterval))
    }

    /// Arrival time is injected, while source timestamps reject delayed observations.
    public mutating func ingest(_ event: ActivityEvent, at time: Date) -> [ActivityContext] {
        guard time >= logicalTime, !recentIDs.contains(event.id),
              event.timestamp >= sourceTimes[event.source, default: .distantPast] else { return [] }
        if case .observationCleared = event.kind {
            observeWithoutEvidence(event, at: time)
            return []
        }
        var output = advance(to: time)
        remember(event)
        let previous = reducer.context
        reducer.apply(event)
        let resources = ActivityResourceExtraction().resources(for: event, accepted: reducer.context)
        if isBoundary(resources, previous: previous) {
            if let context = emit(at: time) { output.append(context) }
            evidence.clear()
        }
        // Rejected shell observations must not invalidate accepted repository evidence.
        if !resources.isEmpty || isInvalidation(event.kind) { evidence.invalidate(for: event.kind) }
        guard !resources.isEmpty else { return output }
        evidence.record(resources, source: event.source, at: time, limit: policy.maximumResources)
        if batchStart == nil { batchStart = time }
        lastChange = time
        return output
    }

    public mutating func advance(to time: Date) -> [ActivityContext] {
        guard time >= logicalTime else { return [] }
        logicalTime = time
        // Emit at the scheduled boundary even if the caller wakes late.
        var result: [ActivityContext] = []
        if let deadline = nextDeadline, deadline <= time, let context = emit(at: deadline) { result.append(context) }
        evidence.expire(before: time.addingTimeInterval(-policy.evidenceLifetime))
        return result
    }

    private mutating func emit(at time: Date) -> ActivityContext? {
        guard let start = batchStart else { return nil }
        batchStart = nil
        lastChange = nil
        evidence.expire(before: time.addingTimeInterval(-policy.evidenceLifetime))
        guard !evidence.entries.isEmpty else { return nil }
        return ActivityContext(startedAt: start, endedAt: time, resources: evidence.entries)
    }

    private mutating func isBoundary(_ resources: [Resource], previous: CurrentContext) -> Bool {
        var changed = false
        for resource in resources {
            if case .terminal(let terminal) = resource, let old = previous.terminal,
               Resource.workingDirectory(old.workingDirectory).id != Resource.workingDirectory(terminal.workingDirectory).id {
                changed = true
                repositoryAnchor = nil
            }
            if case .repository(let repository) = resource {
                if let old = repositoryAnchor {
                    changed = changed || old.identity != repository.identity || old.branch != repository.branch
                }
                repositoryAnchor = repository
            }
        }
        return changed
    }

    private func isInvalidation(_ event: ActivityEventKind) -> Bool {
        switch event {
        case .terminalSessionEnded, .browserFocusCleared, .browserDisconnected, .browserTabClosed,
             .windowClosed, .accessibilityPermissionChanged: true
        default: false
        }
    }

    private mutating func remember(_ event: ActivityEvent) {
        recentIDs.append(event.id)
        if recentIDs.count > 512 { recentIDs.removeFirst() }
        // Source IDs come from bounded integrations; cap replay input as well.
        if sourceTimes[event.source] == nil, sourceTimes.count >= 64 {
            let oldest = sourceTimes.min { ($0.value, $0.key.rawValue) < ($1.value, $1.key.rawValue) }?.key
            if let oldest { sourceTimes.removeValue(forKey: oldest) }
        }
        sourceTimes[event.source] = event.timestamp
    }
}
