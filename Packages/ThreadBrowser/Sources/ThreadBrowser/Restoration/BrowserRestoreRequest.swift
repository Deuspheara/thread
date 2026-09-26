import Foundation
import OSLog

/// Owns one ephemeral reply endpoint and a bounded, cancellation-aware acknowledgment wait.
@MainActor
final class BrowserRestoreRequest {
    private let endpoint: URL
    private let command: BrowserRestoreCommand
    private var listener: UnixDatagramListener?
    private var timeout: Task<Void, Never>?
    private var completion: CheckedContinuation<BrowserRestoreReply, Error>?

    init(endpoint: URL, command: BrowserRestoreCommand) { self.endpoint = endpoint; self.command = command }

    func send(to destination: URL) async throws -> BrowserRestoreReply {
        try await send { data in try BrowserMessageSender().sendControl(data, to: destination) }
    }

    func send(using deliver: @escaping @MainActor @Sendable (Data) async throws -> Void) async throws -> BrowserRestoreReply {
        try command.validate()
        try Task.checkCancellation()
        let payload = try JSONEncoder().encode(command)
        let listener = UnixDatagramListener { [weak self] in self?.receive($0) }
        try listener.start(at: endpoint)
        self.listener = listener
        defer { cleanup() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { completion in
                self.completion = completion
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(4)) }
                    catch { return }
                    self?.finish(.failure(BrowserTransportError.unavailable))
                }
                Task { [weak self] in
                    do { try await deliver(payload) }
                    catch { self?.finish(.failure(error)) }
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    private func receive(_ data: Data) {
        guard data.count <= 1024, let reply = try? JSONDecoder().decode(BrowserRestoreReply.self, from: data),
              (try? reply.validate()) != nil, reply.id == command.id, reply.connection == command.connection else { return }
        finish(.success(reply))
    }

    private func finish(_ result: Result<BrowserRestoreReply, Error>) {
        let pending = completion; completion = nil
        timeout?.cancel(); timeout = nil
        pending?.resume(with: result)
    }

    private func cleanup() {
        timeout?.cancel(); timeout = nil
        listener?.stop(); listener = nil
        // This request owns the UUID-named directory leased above, including its lock file.
        do { try FileManager.default.removeItem(at: endpoint.deletingLastPathComponent()) }
        catch { Logger(subsystem: "app.thread.desktop", category: "browser").error("Restore endpoint cleanup unavailable") }
    }
}
