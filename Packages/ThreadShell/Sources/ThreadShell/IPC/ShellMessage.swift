import Foundation
import ThreadDomain

/// Defines the versioned local wire protocol; command text is deliberately absent.
public struct ShellMessage: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case directory, completed, ended }
    public let version: Int
    public let kind: Kind
    public let session: UUID
    public let processIdentifier: Int32
    public let workingDirectory: String
    public let terminalApplication: String?
    public let sequence: UInt64
    public let exitStatus: Int32?

    public init(kind: Kind, session: UUID, processIdentifier: Int32, workingDirectory: String,
                terminalApplication: String?, sequence: UInt64, exitStatus: Int32? = nil) {
        version = 1
        self.kind = kind
        self.session = session
        self.processIdentifier = processIdentifier
        self.workingDirectory = workingDirectory
        self.terminalApplication = terminalApplication
        self.sequence = sequence
        self.exitStatus = exitStatus
    }

    public func validated() throws -> ShellMessage {
        guard version == 1, processIdentifier > 0, sequence > 0,
              workingDirectory.hasPrefix("/"), !workingDirectory.utf8.contains(0),
              workingDirectory.utf8.count <= 4096,
              terminalApplication.map({ $0.utf8.count <= 128 && !$0.utf8.contains(0) }) ?? true,
              kind != .completed || exitStatus.map({ (0...255).contains($0) }) == true else {
            throw ShellTransportError.invalidMessage
        }
        return self
    }

    var terminal: TerminalContext {
        TerminalContext(session: TerminalSessionIdentity(rawValue: session), processIdentifier: processIdentifier,
                        workingDirectory: workingDirectory, terminalApplication: terminalApplication, sequence: sequence)
    }
}

public enum ShellTransportError: Error, Sendable {
    case invalidMessage, unsafeDirectory, invalidPath, alreadyListening, unavailable, sendFailed
}
