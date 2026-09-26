import Foundation
import ThreadDomain

/// Orders each connection's messages and translates only validated browser metadata into domain events.
struct BrowserConnectionRegistry {
    private struct Entry { let sequence: UInt64; let seen: Date; let disconnected: Bool }
    private var connections: [UUID: Entry] = [:]

    func isConnected(_ id: UUID) -> Bool {
        connections[id].map { !$0.disconnected } ?? false
    }

    mutating func normalize(_ data: Data, at date: Date) throws -> ActivityEventKind? {
        guard data.count <= 8192 else { throw BrowserTransportError.invalidMessage }
        guard let message = try JSONDecoder().decode(BrowserMessage.self, from: data).sanitized() else { return nil }
        if let previous = connections[message.connection], previous.disconnected || message.sequence <= previous.sequence { return nil }
        if connections.count >= 64, connections[message.connection] == nil,
           let oldest = connections.min(by: { $0.value.seen < $1.value.seen })?.key { connections.removeValue(forKey: oldest) }
        connections[message.connection] = Entry(sequence: message.sequence, seen: date, disconnected: message.kind == .disconnected)
        return try event(for: message)
    }

    private func event(for message: BrowserMessage) throws -> ActivityEventKind? {
        let connection = BrowserConnectionIdentity(rawValue: message.connection)
        switch message.kind {
        case .connected: return nil
        case .disconnected: return .browserDisconnected(connection)
        case .focusCleared: return .browserFocusCleared(connection)
        case .closed:
            guard let id = message.tabID else { throw BrowserTransportError.invalidMessage }
            return .browserTabClosed(BrowserTabIdentity(connection: connection, tab: id))
        case .opened, .activated, .updated:
            guard let id = message.tabID, let window = message.windowID, let url = message.url,
                  let domain = URL(string: url)?.host else { throw BrowserTransportError.invalidMessage }
            let context = BrowserTabContext(identity: BrowserTabIdentity(connection: connection, tab: id), browser: message.browser,
                                            window: window, url: url, domain: domain, title: message.title ?? "", isActive: message.active == true, application: message.application)
            switch message.kind {
            case .opened: return .browserTabOpened(context)
            case .activated: return .browserTabActivated(context)
            default: return .browserTabUpdated(context)
            }
        }
    }
}
