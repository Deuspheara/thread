import Foundation
import Testing
import ThreadDomain
import ThreadEngine

struct RepositoryContextTests {
    @Test func lateGitResultCannotAttachToNewerDirectory() {
        var reducer = CurrentContextReducer()
        let session = TerminalSessionIdentity(rawValue: UUID())
        reducer.apply(event(.terminalDirectoryChanged(terminal(session, 1)), at: 1))
        reducer.apply(event(.terminalDirectoryChanged(terminal(session, 2)), at: 2))
        reducer.apply(event(.repositoryChanged(RepositoryObservation(terminal: session, sequence: 1, resolution: .notRepository)), at: 3))
        #expect(reducer.context.repository == nil)
        reducer.apply(event(.repositoryChanged(RepositoryObservation(terminal: session, sequence: 2, resolution: .notRepository)), at: 4))
        #expect(reducer.context.repository == .notRepository)
        reducer.apply(event(.terminalDirectoryChanged(terminal(session, 3)), at: 5))
        #expect(reducer.context.repository == nil)
    }

    @Test func endedSessionRejectsLateGitWithoutAdvancingPresentationTime() {
        var reducer = CurrentContextReducer()
        let session = TerminalSessionIdentity(rawValue: UUID())
        reducer.apply(event(.terminalDirectoryChanged(terminal(session, 1)), at: 1))
        #expect(reducer.context.updatedAt == Date(timeIntervalSince1970: 1))
        reducer.apply(event(.repositoryChanged(RepositoryObservation(terminal: session, sequence: 1,
            resolution: .notRepository)), at: 2))
        #expect(reducer.context.updatedAt == Date(timeIntervalSince1970: 2))
        reducer.apply(event(.terminalSessionEnded(session), at: 3))
        #expect(reducer.context.updatedAt == Date(timeIntervalSince1970: 3))
        reducer.apply(event(.branchChanged(RepositoryObservation(terminal: session, sequence: 1,
            resolution: .notRepository)), at: 4))
        #expect(reducer.context.repository == nil)
        #expect(reducer.context.terminal == nil)
        #expect(reducer.context.updatedAt == Date(timeIntervalSince1970: 3))
        let next = TerminalSessionIdentity(rawValue: UUID())
        reducer.apply(event(.terminalDirectoryChanged(terminal(next, 1)), at: 5))
        #expect(reducer.context.updatedAt == Date(timeIntervalSince1970: 5))
        reducer.apply(event(.repositoryChanged(RepositoryObservation(terminal: session, sequence: 1,
            resolution: .notRepository)), at: 6))
        #expect(reducer.context.repository == nil)
        #expect(reducer.context.updatedAt == Date(timeIntervalSince1970: 5))
    }

    private func terminal(_ session: TerminalSessionIdentity, _ sequence: UInt64) -> TerminalContext {
        TerminalContext(session: session, processIdentifier: 1, workingDirectory: "/tmp", terminalApplication: nil, sequence: sequence)
    }
    private func event(_ kind: ActivityEventKind, at time: TimeInterval) -> ActivityEvent {
        ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: Date(timeIntervalSince1970: time), source: ActivitySourceID(rawValue: "test"), kind: kind)
    }
}
