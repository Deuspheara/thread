import Foundation
import Testing
import ThreadDomain
import ThreadEngine

struct TerminalContextTests {
    @Test func delayedSequenceDoesNotReplaceCWD() {
        var reducer = CurrentContextReducer()
        let id = TerminalSessionIdentity(rawValue: UUID())
        reducer.apply(event(.terminalDirectoryChanged(terminal(id, 2, "/new")), at: 2))
        reducer.apply(event(.terminalDirectoryChanged(terminal(id, 1, "/old")), at: 3))
        #expect(reducer.context.terminal?.workingDirectory == "/new")
    }

    @Test func endingAnotherSessionPreservesCurrentTerminal() {
        var reducer = CurrentContextReducer()
        let id = TerminalSessionIdentity(rawValue: UUID())
        reducer.apply(event(.terminalCommandCompleted(terminal(id, 1, "/project"), 7), at: 1))
        reducer.apply(event(.terminalSessionEnded(TerminalSessionIdentity(rawValue: UUID())), at: 2))
        #expect(reducer.context.terminal?.session == id)
        #expect(reducer.context.terminalExitStatus == 7)
        reducer.apply(event(.terminalSessionEnded(id), at: 3))
        #expect(reducer.context.terminal == nil)
        #expect(reducer.context.terminalExitStatus == nil)
    }

    private func terminal(_ id: TerminalSessionIdentity, _ sequence: UInt64, _ cwd: String) -> TerminalContext {
        TerminalContext(session: id, processIdentifier: 1, workingDirectory: cwd, terminalApplication: nil, sequence: sequence)
    }

    private func event(_ kind: ActivityEventKind, at time: TimeInterval) -> ActivityEvent {
        ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: Date(timeIntervalSince1970: time), source: ActivitySourceID(rawValue: "test"), kind: kind)
    }
}
