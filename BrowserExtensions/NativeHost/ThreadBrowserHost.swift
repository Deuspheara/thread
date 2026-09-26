import Foundation
import ThreadBrowser
import ThreadMacOS
import ThreadDomain

/// Bridges an allowed extension's framed stdio messages to the app's private local socket.
@main
struct ThreadBrowserHost {
    struct Reply: Encodable { let sequence: UInt64; let forwarded: Bool; let instance: String? }
    @MainActor static func main() async {
        guard CommandLine.arguments.dropFirst().first == "chrome-extension://ffjhibkehjmapladhgbmjfpamjpglhcb/" else { exit(1) }
        let application = BrowserHostApplicationIdentity().resolve()
        let framing = NativeMessageFraming()
        let destination = ProcessInfo.processInfo.environment["THREAD_BROWSER_SOCKET"].map { URL(fileURLWithPath: $0) }
            ?? BrowserSocketLocation.defaultURL
        let output = NativeOutput()
        let restoration = BrowserRestoreHost(directory: destination.deletingLastPathComponent(), send: { try await output.write($0) })
        do {
            try await Task.detached { try await bridge(framing: framing, destination: destination, output: output, restoration: restoration, application: application) }.value
            restoration.stop()
        }
        catch { report("Thread: native browser transport rejected a message.\n"); exit(1) }
    }

    private static func bridge(framing: NativeMessageFraming, destination: URL, output: NativeOutput, restoration: BrowserRestoreHost, application: ApplicationIdentity?) async throws {
        var latest: BrowserMessage?
        defer {
            if let latest {
                let end = BrowserMessage(kind: .disconnected, browser: latest.browser, connection: latest.connection, sequence: latest.sequence + 1)
                do { try BrowserMessageSender().send(end, to: destination) }
                catch { report("Thread: browser disconnected while app unavailable.\n") }
            }
        }
        while let bytes = try framing.read(from: .standardInput) {
            struct Envelope: Decodable { let kind: String }
            if try JSONDecoder().decode(Envelope.self, from: bytes).kind == "restoreResult" {
                let result = try JSONDecoder().decode(BrowserRestoreReply.self, from: bytes)
                do { try await restoration.accept(result) }
                catch { report("Thread: restore acknowledgment unavailable.\n") }
                continue
            }
            let decoded = try JSONDecoder().decode(BrowserMessage.self, from: bytes)
            guard let message = try decoded.sanitized()?.identified(by: application) else {
                try await reply(decoded.sequence, forwarded: false, output: output)
                continue
            }
            try await restoration.connect(message.connection)
            latest = message
            do {
                let instance = try BrowserMessageSender().send(message, to: destination)
                try await reply(message.sequence, forwarded: true, instance: instance, output: output)
            } catch {
                try await reply(message.sequence, forwarded: false, output: output)
            }
        }
    }
    private static func reply(_ sequence: UInt64, forwarded: Bool, instance: String? = nil, output: NativeOutput) async throws {
        try await output.write(JSONEncoder().encode(Reply(sequence: sequence, forwarded: forwarded, instance: instance)))
    }
    private static func report(_ message: String) { FileHandle.standardError.write(Data(message.utf8)) }
}
