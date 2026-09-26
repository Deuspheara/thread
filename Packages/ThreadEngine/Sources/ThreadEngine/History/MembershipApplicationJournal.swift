import Foundation
import ThreadDomain

public enum MembershipRecordingFailure: Sendable, Equatable { case invalidRecord, backlogOverflow, writeUnavailable }

/// Batches bounded live-graph membership outcomes and retains failed IDs for retry on the next explicit flush.
public actor MembershipApplicationJournal {
    private let archive: any MembershipApplicationArchive
    private let now: @Sendable () -> Date
    private let onFailure: @Sendable (MembershipRecordingFailure) -> Void
    private var records: [MembershipApplicationRecord] = []
    private var flushTask: (id: UUID, task: Task<Bool, Never>)?
    private var overflowReported = false
    private var writeFailureReported = false
    private var cleanupPending = false

    public init(archive: any MembershipApplicationArchive, now: @escaping @Sendable () -> Date = { Date() },
                onFailure: @escaping @Sendable (MembershipRecordingFailure) -> Void) {
        self.archive = archive
        self.now = now
        self.onFailure = onFailure
    }

    /// Startup retention runs only after the composition root has prepared storage.
    public func prepare() async { cleanupPending = true; await flush() }

    public func record(_ record: MembershipApplicationRecord) {
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
            do { try await archive.append(applications: batch, at: now(), retention: DecisionRetentionPolicy()) }
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
