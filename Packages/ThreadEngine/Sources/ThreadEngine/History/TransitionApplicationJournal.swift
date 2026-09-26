import Foundation
import ThreadDomain

public enum TransitionRecordingFailure: Sendable, Equatable { case invalidRecord, backlogOverflow, writeUnavailable }

/// Batches bounded live-graph transition outcomes and retains failed IDs for retry on the next explicit flush.
public actor TransitionApplicationJournal {
    private let archive: any TransitionApplicationArchive
    private let now: @Sendable () -> Date
    private let onFailure: @Sendable (TransitionRecordingFailure) -> Void
    private var records: [TransitionApplicationRecord] = []
    private var flushTask: (id: UUID, task: Task<Bool, Never>)?
    private var overflowReported = false
    private var writeFailureReported = false
    private var cleanupPending = false

    public init(archive: any TransitionApplicationArchive, now: @escaping @Sendable () -> Date = { Date() },
                onFailure: @escaping @Sendable (TransitionRecordingFailure) -> Void) {
        self.archive = archive
        self.now = now
        self.onFailure = onFailure
    }

    /// Startup retention runs only after the composition root has prepared storage.
    public func prepare() async { cleanupPending = true; await flush() }

    public func record(_ record: TransitionApplicationRecord) {
        guard record.isValid else { onFailure(.invalidRecord); return }
        guard !records.contains(where: { $0.id == record.id }) else { return }
        records.append(record)
        if records.count > 256 {
            records.removeFirst(records.count - 256)
            if !overflowReported { onFailure(.backlogOverflow); overflowReported = true }
        }
    }

    /// Concurrent callers await the same write; shutdown cannot race an outstanding presentation flush.
    public func flush() async {
        guard !records.isEmpty || cleanupPending || flushTask != nil else { return }
        repeat {
            let active: (id: UUID, task: Task<Bool, Never>)
            if let running = flushTask { active = running }
            else {
                active = (UUID(), Task { await drain() })
                flushTask = active
            }
            let saved = await active.task.value
            if flushTask?.id == active.id { flushTask = nil }
            guard saved else { return }
        } while !records.isEmpty || cleanupPending || flushTask != nil
    }

    private func drain() async -> Bool {
        while !records.isEmpty || cleanupPending {
            let batch = records
            do { try await archive.append(transitions: batch, at: now(), retention: DecisionRetentionPolicy()) }
            catch {
                if !writeFailureReported { onFailure(.writeUnavailable); writeFailureReported = true }
                return false
            }
            let committed = Set(batch.map(\.id))
            records.removeAll { committed.contains($0.id) }
            overflowReported = false
            writeFailureReported = false
            cleanupPending = false
        }
        return true
    }
}
