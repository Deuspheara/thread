import Foundation
import ThreadDomain

/// Rejects duplicate/out-of-order session datagrams before creating domain events.
struct ShellSessionRegistry {
    private struct Entry { let sequence: UInt64; let seen: Date; let ended: Bool; let processIdentifier: Int32 }
    private var sessions: [UUID: Entry] = [:]

    var retainedSessions: Set<TerminalSessionIdentity> {
        Set(sessions.keys.map { TerminalSessionIdentity(rawValue: $0) })
    }

    mutating func end(_ session: TerminalSessionIdentity, at now: Date) -> ActivityEventKind? {
        guard let entry = sessions[session.rawValue], !entry.ended else { return nil }
        sessions[session.rawValue] = Entry(sequence: entry.sequence, seen: now, ended: true, processIdentifier: entry.processIdentifier)
        return .terminalSessionEnded(session)
    }

    mutating func normalize(_ data: Data, at now: Date) throws -> ActivityEventKind? {
        guard data.count <= 8192 else { throw ShellTransportError.invalidMessage }
        let message = try JSONDecoder().decode(ShellMessage.self, from: data).validated()
        if let previous = sessions[message.session], previous.ended || message.sequence <= previous.sequence { return nil }
        if let previous = sessions[message.session], previous.processIdentifier != message.processIdentifier {
            throw ShellTransportError.invalidMessage
        }
        if sessions.count >= 256, sessions[message.session] == nil,
           let oldest = sessions.min(by: { $0.value.seen < $1.value.seen })?.key { sessions.removeValue(forKey: oldest) }
        // Retain terminal tombstones so later datagrams cannot revive an ended session.
        sessions[message.session] = Entry(sequence: message.sequence, seen: now, ended: message.kind == .ended, processIdentifier: message.processIdentifier)
        switch message.kind {
        case .directory: return .terminalDirectoryChanged(message.terminal)
        case .completed: return .terminalCommandCompleted(message.terminal, message.exitStatus!)
        case .ended: return .terminalSessionEnded(message.terminal.session)
        }
    }
}
