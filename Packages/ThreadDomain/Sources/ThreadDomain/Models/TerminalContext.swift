import Foundation

public struct TerminalSessionIdentity: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// Describes a shell prompt without command contents or terminal output.
public struct TerminalContext: Equatable, Codable, Sendable {
    public let session: TerminalSessionIdentity
    public let processIdentifier: Int32
    public let workingDirectory: String
    public let terminalApplication: String?
    public let sequence: UInt64

    public init(session: TerminalSessionIdentity, processIdentifier: Int32, workingDirectory: String,
                terminalApplication: String?, sequence: UInt64) {
        self.session = session
        self.processIdentifier = processIdentifier
        self.workingDirectory = workingDirectory
        self.terminalApplication = terminalApplication
        self.sequence = sequence
    }
}
