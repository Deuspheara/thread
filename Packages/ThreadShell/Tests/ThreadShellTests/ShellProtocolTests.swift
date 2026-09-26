import Foundation
import Testing
import ThreadDomain
@testable import ThreadShell

struct ShellProtocolTests {
    @Test func duplicateAndDelayedMessagesCannotResurrectEndedSession() throws {
        let id = UUID()
        var registry = ShellSessionRegistry()
        let first = message(session: id, sequence: 1)
        let ended = message(session: id, sequence: 3, kind: .ended)
        #expect(try registry.normalize(JSONEncoder().encode(first), at: .distantPast) != nil)
        #expect(try registry.normalize(JSONEncoder().encode(first), at: .distantPast) == nil)
        #expect(try registry.normalize(JSONEncoder().encode(ended), at: .distantPast) == .terminalSessionEnded(TerminalSessionIdentity(rawValue: id)))
        #expect(try registry.normalize(JSONEncoder().encode(message(session: id, sequence: 2)), at: .distantPast) == nil)
        #expect(try registry.normalize(JSONEncoder().encode(message(session: id, sequence: 4)), at: .distantPast) == nil)
        #expect(try registry.normalize(JSONEncoder().encode(message(session: id, sequence: 5, kind: .ended)), at: .distantPast) == nil)
        #expect(try registry.normalize(JSONEncoder().encode(message(session: UUID(), sequence: 1)), at: .distantPast) != nil)
    }

    @Test func rejectsInvalidVersionStatusAndOversizedPayload() throws {
        let valid = message(session: UUID(), sequence: 1)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
        object["version"] = 99
        var registry = ShellSessionRegistry()
        #expect(throws: (any Error).self) { try registry.normalize(JSONSerialization.data(withJSONObject: object), at: .distantPast) }
        #expect(throws: (any Error).self) { try registry.normalize(Data(repeating: 0, count: 8193), at: .distantPast) }
        let bad = ShellMessage(kind: .completed, session: UUID(), processIdentifier: 1, workingDirectory: "/tmp",
                               terminalApplication: nil, sequence: 1, exitStatus: 256)
        #expect(throws: (any Error).self) { try bad.validated() }
    }

    @Test func sessionCannotChangeItsProcessIdentifier() throws {
        let session = UUID()
        var registry = ShellSessionRegistry()
        _ = try registry.normalize(JSONEncoder().encode(message(session: session, sequence: 1)), at: .distantPast)
        let changed = ShellMessage(kind: .directory, session: session, processIdentifier: 2,
            workingDirectory: "/tmp", terminalApplication: nil, sequence: 2)
        #expect(throws: ShellTransportError.self) {
            try registry.normalize(JSONEncoder().encode(changed), at: .distantPast)
        }
    }

    @Test func preservesLiteralPathsWithoutInterpretingShellSyntax() throws {
        let value = ShellMessage(kind: .directory, session: UUID(), processIdentifier: 1,
                                 workingDirectory: "/tmp/a 'quoted' $(touch never)\nfolder", terminalApplication: nil, sequence: 1)
        var registry = ShellSessionRegistry()
        let result = try registry.normalize(JSONEncoder().encode(value), at: .distantPast)
        guard case .terminalDirectoryChanged(let terminal) = result else { Issue.record("Expected terminal event"); return }
        #expect(terminal.workingDirectory == value.workingDirectory)
    }

    private func message(session: UUID, sequence: UInt64, kind: ShellMessage.Kind = .directory) -> ShellMessage {
        ShellMessage(kind: kind, session: session, processIdentifier: 1, workingDirectory: "/tmp/project",
                     terminalApplication: "test", sequence: sequence)
    }
}
