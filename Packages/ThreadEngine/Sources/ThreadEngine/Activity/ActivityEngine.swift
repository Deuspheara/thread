import Foundation
import ThreadDomain

/// Schedules bounded, serial inference and one-shot reviews while keeping observation responsive.
public actor ActivityEngine: ThreadEditing, RestorationFocus {
    private let graph: ThreadGraphStore
    private let inference: ActivityInference
    private let history: GraphHistory?
    private let archive: (any ActivityArchive)?
    private let onTransitionApplication: (@Sendable (TransitionApplicationRecord) async -> Void)?
    private let onResourceReassignment: (@Sendable (ResourceReassignmentRecord) async -> Void)?
    private var journal = ActivityJournal()
    private let retention = HistoryRetentionPolicy()
    private var historyStatus: HistoryStatus
    private var hydrated: Bool
    private var hydration: Task<Void, Error>?
    private var saveRequested = false
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var aggregator: EventAggregator
    private var transitions: TransitionPolicy
    private var pending: [(ActivityContext, UInt64)] = []
    private var edits: [(ActivityUserCommand, CheckedContinuation<HistoryStatus, Error>)] = []
    private var restoring: (token: UUID, thread: ThreadID)?
    private var revision: UInt64 = 0
    private var publication: UInt64 = 0
    private var timerRevision: UInt64 = 0
    private var worker: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var review: (thread: ThreadID, decision: TransitionDecision, revision: UInt64)?
    private var stopped = false
    private var failure: ActivityFailure?
    private nonisolated let stream: AsyncStream<ThreadOverview>
    private let continuation: AsyncStream<ThreadOverview>.Continuation

    public init(graph: ThreadGraphStore, decisions: any DecisionEngine, repository: (any ThreadRepository)? = nil, archive: (any ActivityArchive)? = nil, policy: AggregationPolicy = AggregationPolicy(),
                transitionPolicy: TransitionPolicy = TransitionPolicy(),
                onMembershipApplication: (@Sendable (MembershipApplicationRecord) async -> Void)? = nil,
                onTransitionApplication: (@Sendable (TransitionApplicationRecord) async -> Void)? = nil,
                onResourceReassignment: (@Sendable (ResourceReassignmentRecord) async -> Void)? = nil,
                now: @escaping @Sendable () -> Date = Date.init,
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        precondition(archive == nil || repository != nil)
        self.archive = archive
        self.onTransitionApplication = onTransitionApplication
        self.onResourceReassignment = onResourceReassignment
        transitions = transitionPolicy
        self.graph = graph
        history = repository.map { GraphHistory(repository: $0) }
        hydrated = repository == nil
        historyStatus = repository == nil ? .sessionOnly : .loading
        inference = ActivityInference(graph: graph, decisions: decisions, onApplication: onMembershipApplication)
        aggregator = EventAggregator(policy: policy)
        self.now = now
        self.sleep = sleep
        let channel = AsyncStream<ThreadOverview>.makeStream(bufferingPolicy: .bufferingNewest(1))
        stream = channel.stream
        continuation = channel.continuation
    }

    public nonisolated func updates() -> AsyncStream<ThreadOverview> { stream }

    public func edit(_ edit: ThreadEdit) async throws -> HistoryStatus { try await enqueue(.edit(edit)) }

    public func beginRestoration(_ thread: ThreadID) async throws -> UUID {
        let token = UUID()
        _ = try await enqueue(.beginRestoration(token, thread))
        return token
    }

    public func endRestoration(_ token: UUID) async throws {
        guard !stopped, restoring?.token == token else { return }
        _ = try await enqueue(.endRestoration(token))
    }

    private func enqueue(_ command: ActivityUserCommand) async throws -> HistoryStatus {
        guard !stopped, hydrated else { throw ThreadEditError.unavailable }
        if case .endRestoration = command { /* The owner must always be able to release suppression. */ }
        else if edits.count >= 32 { throw ThreadEditError.busy }
        return try await withCheckedThrowingContinuation { continuation in
            edits.append((command, continuation))
            revision &+= 1
            transitions.cancelPending()
            review = nil
            startWorker()
        }
    }

    private func applyNextEdit() async {
        let (command, completion) = edits.removeFirst()
        do {
            switch command {
            case .edit(let edit):
                if let record = try await graph.edit(edit, at: now()) { await onResourceReassignment?(record) }
                if case .archive(let id, true) = edit { transitions.remove(id) }
                if case .split = edit {
                    pending.removeAll()
                    aggregator.discardEvidence()
                }
                if case .merge(let source, let target) = edit {
                    if transitions.active == source { transitions.select(target, at: now()) }
                    pending.removeAll()
                    aggregator.discardEvidence()
                }
            case .beginRestoration(let token, let thread):
                guard restoring == nil else { throw ThreadRestoreError.busy }
                try await graph.recordSelection(thread, at: now())
                restoring = (token, thread)
                pending.removeAll()
                aggregator.discardEvidence()
                transitions.select(thread, at: now())
            case .endRestoration(let token):
                if let session = restoring, session.token == token {
                    if let detail = await graph.detail(session.thread), !detail.thread.isArchived {
                        transitions.select(session.thread, at: now())
                    }
                    restoring = nil
                    aggregator.discardEvidence()
                }
            }
            schedule()
            await saveHistory()
            await publish()
            completion.resume(returning: historyStatus)
        } catch { completion.resume(throwing: error) }
    }

    public func prepareHistory() async throws {
        guard !stopped else { throw HistoryLifecycleError.stopped }
        if hydrated {
            if historyStatus == .unsaved {
                saveRequested = true
                startWorker()
                await worker?.value
                if historyStatus == .unsaved { throw HistoryLifecycleError.saveFailed }
            }
            return
        }
        if let hydration { return try await hydration.value }
        let task = Task { try await hydrate() }
        hydration = task
        defer { hydration = nil }
        try await task.value
    }

    public func historyPreparationFailed() async {
        guard !stopped, !hydrated, historyStatus != .unavailable else { return }
        historyStatus = .unavailable
        await publish()
    }

    private func hydrate() async throws {
        guard let history else { return }
        historyStatus = .loading
        do {
            let state = try await history.load()
            try Task.checkCancellation()
            guard !stopped else { throw HistoryLifecycleError.stopped }
            try await graph.restore(state)
            hydrated = true
            historyStatus = .saved
            await saveHistory()
            await publish()
            startWorker()
            if historyStatus == .unsaved { throw HistoryLifecycleError.saveFailed }
        } catch {
            if !hydrated { historyStatus = .unavailable }
            await publish()
            throw error
        }
    }

    public func ingest(_ event: ActivityEvent) {
        guard !stopped else { return }
        let time = now()
        if case .observationCleared = event.kind {
            aggregator.observeWithoutEvidence(event, at: time)
            pending.removeAll()
            revision &+= 1
            review = nil
            transitions.cancelPending()
            schedule()
            return
        }
        if restoring != nil {
            aggregator.observeWithoutEvidence(event, at: time)
            return
        }
        if archive != nil, journal.record(event, at: time) { failure = .backlogOverflow }
        let contexts = aggregator.ingest(event, at: time)
        // Emissions preceding this event are historical; they may update membership, not active focus.
        enqueue(contexts, revision: revision)
        revision &+= 1
        review = nil
        transitions.cancelPending()
        schedule()
    }

    @discardableResult
    public func stop() async -> HistoryStatus {
        guard !stopped else { return historyStatus }
        stopped = true
        timer?.cancel()
        worker?.cancel()
        pending.removeAll()
        for (_, completion) in edits { completion.resume(throwing: ThreadEditError.unavailable) }
        edits.removeAll()
        hydration?.cancel()
        _ = await hydration?.result
        await worker?.value
        await saveHistory()
        continuation.finish()
        worker = nil
        timer = nil
        return historyStatus
    }

    private func enqueue(_ contexts: [ActivityContext], revision: UInt64) {
        pending.append(contentsOf: contexts.map { ($0, revision) })
        if pending.count > 16 {
            pending.removeFirst(pending.count - 16)
            failure = .backlogOverflow
        }
        startWorker()
    }

    private func startWorker() {
        if !stopped, hydrated, worker == nil, !pending.isEmpty || !edits.isEmpty || saveRequested { worker = Task { await drain() } }
    }

    private func drain() async {
        while !stopped, !Task.isCancelled, !pending.isEmpty || !edits.isEmpty || saveRequested {
            if !edits.isEmpty {
                await applyNextEdit()
                continue
            }
            if pending.isEmpty {
                saveRequested = false
                await saveHistory()
                await publish()
                continue
            }
            let (context, version) = pending.removeFirst()
            do {
                let outcome = try await inference.process(context, active: transitions.active)
                guard !stopped, !Task.isCancelled else { break }
                if archive != nil, let target = outcome.thread, let detail = await graph.detail(target) {
                    if journal.capture(detail, at: now()) { failure = .backlogOverflow }
                }
                if failure != .backlogOverflow { failure = nil }
                if let target = outcome.thread {
                    await applyTransition(target, decision: outcome.transition, version: version, phase: .context, at: now())
                } else if version == revision {
                    transitions.cancelPending(); review = nil
                }
            } catch is CancellationError {
                break
            } catch {
                failure = .inferenceUnavailable
                transitions.cancelPending()
                review = nil
            }
            await saveHistory()
            await publish()
            schedule()
        }
        worker = nil
    }

    /// Records policy acceptance before awaiting external recording; obsolete contexts never change focus.
    private func applyTransition(_ target: ThreadID, decision: TransitionDecision, version: UInt64,
                                 phase: TransitionApplicationPhase, at time: Date) async {
        let previous = transitions.active
        let outcome = version == revision ? transitions.consider(target, decision: decision, at: time) : .obsoleteContext
        if version == revision {
            review = phase == .context && transitions.nextReviewAt != nil ? (target, decision, version) : nil
        }
        guard let onTransitionApplication else { return }
        await onTransitionApplication(TransitionApplicationRecord(id: .init(rawValue: UUID()), timestamp: time,
            phase: phase, outcome: outcome, previous: previous, target: target, decisionRecordID: decision.recordID))
    }

    private func saveHistory() async {
        guard hydrated, let history else { return }
        do {
            try await history.save(graph.checkpoint())
            if let archive {
                let batch = journal.batch()
                try await archive.append(events: batch.events, snapshots: batch.snapshots, at: now(), retention: retention)
                journal.acknowledge(batch, at: now())
            }
            historyStatus = .saved
        } catch {
            journal.pauseDeadline()
            historyStatus = .unsaved
        }
    }

    private func schedule() {
        timer?.cancel()
        timerRevision &+= 1
        guard !stopped else { return }
        let dates = [aggregator.nextDeadline, review == nil ? nil : transitions.nextReviewAt, hydrated ? journal.deadline : nil].compactMap { $0 }
        guard let deadline = dates.min() else { timer = nil; return }
        let token = timerRevision
        let delay = max(0, deadline.timeIntervalSince(now()))
        timer = Task { [sleep] in
            do { try await sleep(delay); await wake(token: token) }
            catch is CancellationError { /* Replaced deadline or shutdown. */ }
            catch { await clockFailed(token: token) }
        }
    }

    private func wake(token: UInt64) async {
        guard !stopped, token == timerRevision else { return }
        let time = now()
        if let deadline = journal.deadline, deadline <= time, hydrated {
            journal.pauseDeadline()
            saveRequested = true
        }
        enqueue(aggregator.advance(to: time), revision: revision)
        if let review, review.revision == revision, let deadline = transitions.nextReviewAt, deadline <= time {
            self.review = nil
            await applyTransition(review.thread, decision: review.decision, version: review.revision, phase: .review, at: time)
            await publish()
        }
        schedule()
    }

    private func clockFailed(token: UInt64) async {
        guard !stopped, token == timerRevision else { return }
        failure = .clockUnavailable
        await publish()
    }

    private func publish() async {
        publication &+= 1
        let token = publication
        let details = await graph.details()
        guard !stopped, token == publication else { return }
        continuation.yield(ThreadOverview(threads: details, active: transitions.active, failure: failure, history: historyStatus))
    }
}
