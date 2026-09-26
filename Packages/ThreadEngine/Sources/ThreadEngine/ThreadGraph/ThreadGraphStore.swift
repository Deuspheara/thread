import Foundation
import ThreadDomain

public enum ThreadGraphError: Error, Sendable { case unknownThread, archivedThread, identityCollision, invalidConfidence, invalidTitle, graphNotEmpty }

/// Owns graph mutations and ensures explicit user reassignment outranks later inference.
public actor ThreadGraphStore {
    private var threads: [ThreadID: ThreadDomain.Thread] = [:]
    private var relationships: [ThreadID: [ResourceID: ThreadResource]] = [:]
    private var corrections: [ResourceID: ThreadID] = [:]
    private let makeID: @Sendable () -> ThreadID

    public init(makeID: @escaping @Sendable () -> ThreadID = { ThreadID(rawValue: UUID()) }) { self.makeID = makeID }

    public func checkpoint() -> ThreadGraphState {
        let overrides = corrections.map { ResourceCorrection(resource: $0.key, thread: $0.value) }.sorted {
            stableKey($0.resource).lexicographicallyPrecedes(stableKey($1.resource))
        }
        let saved = details().map { ThreadDetail(thread: $0.thread, resources: $0.resources.filter { $0.persistence == .durable }) }
        return ThreadGraphState(threads: saved, corrections: overrides)
    }

    public func restore(_ state: ThreadGraphState) throws {
        guard threads.isEmpty, corrections.isEmpty else { throw ThreadGraphError.graphNotEmpty }
        try ThreadGraphValidation.validate(state)
        threads = Dictionary(uniqueKeysWithValues: state.threads.map { ($0.thread.id, $0.thread) })
        relationships = Dictionary(uniqueKeysWithValues: state.threads.map { detail in
            (detail.thread.id, Dictionary(uniqueKeysWithValues: detail.resources.map { ($0.resource.id, $0) }))
        })
        corrections = Dictionary(uniqueKeysWithValues: state.corrections.map { ($0.resource, $0.thread) })
    }

    @discardableResult
    public func apply(_ authorization: MembershipAuthorization, confidence: Double, context: ActivityContext,
                      persistence: [ResourceID: PersistenceDisposition] = [:], membershipRecordID: DecisionRecordID? = nil) throws -> ThreadID? {
        guard confidence.isFinite, (0...1).contains(confidence) else { throw ThreadGraphError.invalidConfidence }
        let observed = context
        let context = attachableContext(context, authorization: authorization, persistence: persistence)
        let target: ThreadID
        let status: MembershipStatus
        switch authorization {
        case .wait, .automatic(.undetermined): return nil
        case .provisional(let id): target = id; status = .provisional
        case .automatic(.existing(let id)): target = id; status = .confirmed
        case .automatic(.newThread):
            let eligible = context.resources.filter { corrections[$0.resource.id] == nil }
            guard eligible.contains(where: { isAnchor($0.resource) }) else { return nil }
            target = makeID()
            guard threads[target] == nil else { throw ThreadGraphError.identityCollision }
            let filtered = ActivityContext(startedAt: context.startedAt, endedAt: context.endedAt, resources: eligible)
            threads[target] = ThreadDomain.Thread(id: target, title: ThreadTitleSuggestion().title(for: filtered),
                                                  createdAt: context.endedAt, lastActiveAt: context.endedAt)
            status = .confirmed
        }
        guard var thread = threads[target] else { throw ThreadGraphError.unknownThread }
        guard !thread.isArchived else { throw ThreadGraphError.archivedThread }
        if status == .confirmed { discardInferredResources(observed, thread: target, persistence: persistence) }
        var attached = false
        for evidence in context.resources {
            guard corrections[evidence.resource.id].map({ $0 == target }) ?? true else { continue }
            if update(evidence, thread: target, status: status, confidence: confidence,
                      persistence: persistence[evidence.resource.id] ?? .durable,
                      membershipRecordID: membershipRecordID) { attached = true }
        }
        guard attached else { return nil }
        if status == .confirmed { thread.lastActiveAt = max(thread.lastActiveAt, context.endedAt) }
        threads[target] = thread
        return target
    }

    private func attachableContext(_ context: ActivityContext, authorization: MembershipAuthorization,
                                   persistence: [ResourceID: PersistenceDisposition]) -> ActivityContext {
        let targetID: ThreadID?
        switch authorization {
        case .automatic(.existing(let id)), .provisional(let id): targetID = id
        default: targetID = nil
        }
        let resources = context.resources.filter { evidence in
            let edge = targetID.flatMap { relationships[$0]?[evidence.resource.id] }
            return persistence[evidence.resource.id] != .discard || edge?.userCorrected == true || edge?.pinned == true
        }
        return ActivityContext(startedAt: context.startedAt, endedAt: context.endedAt, resources: resources)
    }

    private func discardInferredResources(_ context: ActivityContext, thread: ThreadID,
                                          persistence: [ResourceID: PersistenceDisposition]) {
        for evidence in context.resources where persistence[evidence.resource.id] == .discard {
            guard let edge = relationships[thread]?[evidence.resource.id], !edge.userCorrected, !edge.pinned,
                  evidence.lastSeen >= edge.lastSeen else { continue }
            relationships[thread]?.removeValue(forKey: evidence.resource.id)
        }
    }

    public func candidates() -> [ThreadCandidate] {
        threads.values.filter { !$0.isArchived }.map { thread in
            let confirmed = relationships[thread.id, default: [:]].values.filter { $0.status == .confirmed }
            return ThreadCandidate(id: thread.id, title: thread.title, lastActiveAt: thread.lastActiveAt,
                                   resourceIDs: Set(confirmed.map { $0.resource.id }),
                                   projectDirectories: Set(confirmed.compactMap { edge in
                                       switch edge.resource {
                                       case .repository(let repository): repository.rootPath
                                       case .workingDirectory(let path): path
                                       default: nil
                                       }
                                   }))
        }
    }

    private func orderedThreads() -> [ThreadDomain.Thread] {
        threads.values.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.lastActiveAt != $1.lastActiveAt { return $0.lastActiveAt > $1.lastActiveAt }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
    }

    public func details() -> [ThreadDetail] { orderedThreads().map { makeDetail($0) } }

    func summaryRows(limit: Int) -> [ThreadSummary] {
        orderedThreads().filter { !$0.isArchived }.prefix(limit).map { thread in
            let edges = relationships[thread.id, default: [:]].values.filter { $0.status == .confirmed }
            let names = Set(edges.compactMap { edge -> String? in
                guard case .application(let app) = edge.resource else { return nil }
                return app.name
            }).sorted().prefix(3)
            return ThreadSummary(thread: thread, resourceCount: edges.count, applications: Array(names))
        }
    }

    func destinationRows(query: String, excluding thread: ThreadID, limit: Int) -> [ThreadDomain.Thread] {
        let text = String(query.prefix(256)).trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(orderedThreads().filter {
            !$0.isArchived && $0.id != thread && (text.isEmpty || $0.title.localizedCaseInsensitiveContains(text))
        }.prefix(limit))
    }

    public func detail(_ id: ThreadID) -> ThreadDetail? { threads[id].map { makeDetail($0) } }

    private func makeDetail(_ thread: ThreadDomain.Thread) -> ThreadDetail {
        ThreadDetail(thread: thread, resources: relationships[thread.id, default: [:]].values.sorted {
            if $0.firstSeen != $1.firstSeen { return $0.firstSeen < $1.firstSeen }
            return stableKey($0.resource.id).lexicographicallyPrecedes(stableKey($1.resource.id))
        })
    }

    public func recordSelection(_ id: ThreadID, at time: Date) throws {
        guard var thread = threads[id] else { throw ThreadGraphError.unknownThread }
        guard !thread.isArchived else { throw ThreadGraphError.archivedThread }
        thread.lastActiveAt = max(thread.lastActiveAt, time)
        threads[id] = thread
    }

    public func rename(_ id: ThreadID, title: String) throws {
        guard var thread = threads[id] else { throw ThreadGraphError.unknownThread }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 160 else { throw ThreadGraphError.invalidTitle }
        thread.title = title
        threads[id] = thread
    }

    public func split(_ source: ThreadID, into destination: ThreadID, title: String,
                      resources: Set<ResourceID>, at time: Date) throws {
        guard threads[destination] == nil else { throw ThreadGraphError.identityCollision }
        guard let from = detail(source) else { throw ThreadGraphError.unknownThread }
        let plan = try ThreadSplitPlan(source: from, destination: destination, title: title, selection: resources, at: time)
        for id in Array(relationships.keys) {
            for resource in resources { relationships[id]?.removeValue(forKey: resource) }
        }
        threads[destination] = plan.thread
        relationships[destination] = plan.resources
        for resource in resources { corrections[resource] = destination }
    }

    public func merge(_ source: ThreadID, into destination: ThreadID) throws {
        guard let from = detail(source), let to = detail(destination) else { throw ThreadGraphError.unknownThread }
        let plan = try ThreadMergePlan(source: from, destination: to)
        threads[source] = plan.source
        threads[destination] = plan.destination
        relationships[source] = [:]
        relationships[destination] = plan.resources
        for (resource, owner) in corrections where owner == source { corrections[resource] = destination }
    }

    public func pin(_ id: ThreadID, pinned: Bool) throws {
        guard var thread = threads[id] else { throw ThreadGraphError.unknownThread }
        thread.isPinned = pinned
        threads[id] = thread
    }

    public func archive(_ id: ThreadID, archived: Bool) throws {
        guard var thread = threads[id] else { throw ThreadGraphError.unknownThread }
        thread.isArchived = archived
        threads[id] = thread
    }

    public func reassign(_ evidence: ResourceEvidence, to id: ThreadID) throws {
        guard threads[id] != nil else { throw ThreadGraphError.unknownThread }
        let resourceID = evidence.resource.id
        corrections[resourceID] = id
        for other in Array(relationships.keys) where other != id { relationships[other]?.removeValue(forKey: resourceID) }
        update(evidence, thread: id, status: .confirmed, confidence: 1)
        relationships[id]?[resourceID]?.status = .confirmed
        relationships[id]?[resourceID]?.userCorrected = true
        relationships[id]?[resourceID]?.confidence = 1
        relationships[id]?[resourceID]?.persistence = .durable
        relationships[id]?[resourceID]?.membershipRecordID = nil
    }

    @discardableResult
    private func update(_ evidence: ResourceEvidence, thread: ThreadID, status: MembershipStatus, confidence: Double,
                        persistence: PersistenceDisposition = .durable, membershipRecordID: DecisionRecordID? = nil) -> Bool {
        let id = evidence.resource.id
        if var existing = relationships[thread]?[id] {
            guard evidence.lastSeen >= existing.lastSeen else { return false }
            // Weak evidence must not overwrite a confirmed restoration snapshot.
            guard status == .confirmed || existing.status == .provisional else { return false }
            existing.resource = evidence.resource
            existing.lastSeen = evidence.lastSeen
            existing.source = evidence.source
            if !existing.userCorrected {
                existing.confidence = confidence; existing.status = status
                existing.membershipRecordID = membershipRecordID
            }
            if !existing.userCorrected && !existing.pinned { existing.persistence = persistence }
            relationships[thread]?[id] = existing
        } else {
            relationships[thread, default: [:]][id] = ThreadResource(resource: evidence.resource, confidence: confidence,
                firstSeen: evidence.firstSeen, lastSeen: evidence.lastSeen, source: evidence.source, status: status,
                persistence: persistence, membershipRecordID: membershipRecordID)
        }
        return true
    }

    private func isAnchor(_ resource: Resource) -> Bool {
        switch resource { case .repository, .branch, .workingDirectory, .file, .browserPage: true; default: false }
    }

    private func stableKey(_ id: ResourceID) -> [String] {
        switch id {
        case .application(let app): ["application", app.bundleIdentifier]
        case .window(let window): ["window", window.rawValue.uuidString]
        case .browserPage(let browser, let url): ["browser", browser.rawValue, url]
        case .terminal(let session): ["terminal", session.rawValue.uuidString]
        case .workingDirectory(let path): ["directory", path]
        case .repository(let repository): ["repository", repository.commonDirectory]
        case .branch(let repository, let branch): ["branch", repository.commonDirectory, branch]
        case .file(let file): ["file", file.path]
        }
    }
}
