import Foundation
import OSLog

/// Bridges connection-scoped local requests to extension messages and routes acknowledgments back.
@MainActor
public final class BrowserRestoreHost {
    private let endpoints: BrowserRestoreEndpoint
    private let send: @Sendable (Data) async throws -> Void
    private var connection: String?
    private var listener: UnixDatagramListener?
    private var pending: [String: Task<Void, Never>] = [:]

    public init(directory: URL, send: @escaping @Sendable (Data) async throws -> Void) {
        endpoints = BrowserRestoreEndpoint(root: directory); self.send = send
    }

    public func connect(_ id: UUID) throws {
        let value = id.uuidString.lowercased()
        if connection == value { return }
        stop()
        let listener = UnixDatagramListener { [weak self] data in self?.receive(data) }
        try listener.start(at: endpoints.host(value))
        self.listener = listener; connection = value
    }

    public func accept(_ reply: BrowserRestoreReply) throws {
        try reply.validate()
        guard reply.connection == connection, let timeout = pending.removeValue(forKey: reply.id) else { return }
        timeout.cancel()
        try BrowserMessageSender().sendControl(JSONEncoder().encode(reply), to: endpoints.reply(reply.id))
    }

    public func stop() {
        listener?.stop(); listener = nil
        if let connection {
            do { try FileManager.default.removeItem(at: endpoints.host(connection).deletingLastPathComponent()) }
            catch { Logger(subsystem: "app.thread.desktop", category: "browser").error("Browser restore host cleanup unavailable") }
        }
        connection = nil
        for timeout in pending.values { timeout.cancel() }
        pending.removeAll()
    }

    isolated deinit { stop() }

    private func receive(_ data: Data) {
        guard data.count <= 8192, let command = try? JSONDecoder().decode(BrowserRestoreCommand.self, from: data),
              (try? command.validate()) != nil, command.connection == connection,
              pending[command.id] == nil, pending.count < 16 else { return }
        pending[command.id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
            self?.pending.removeValue(forKey: command.id)
        }
        Task { [weak self, send] in
            do { try await send(JSONEncoder().encode(command)) }
            catch { self?.pending.removeValue(forKey: command.id)?.cancel() }
        }
    }
}
