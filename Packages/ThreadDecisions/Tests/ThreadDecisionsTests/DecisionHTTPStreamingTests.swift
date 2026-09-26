import Foundation
import Testing
@testable import ThreadDecisions

struct DecisionHTTPStreamingTests {
    @Test func realHTTPStreamIsBoundedAndRedirectDestinationIsNeverRequested() async throws {
        let fixture = try DecisionHTTPFixture()
        defer { fixture.stop() }
        let transport = URLSessionDecisionTransport()
        let valid = try await transport.send(URLRequest(url: fixture.url("valid")))
        #expect(String(decoding: valid, as: UTF8.self) == "{}")
        await #expect(throws: RemoteDecisionError.responseTooLarge) {
            try await transport.send(URLRequest(url: fixture.url("oversized")))
        }
        await #expect(throws: RemoteDecisionError.invalidResponse) {
            try await transport.send(URLRequest(url: fixture.url("redirect")))
        }
        let requests = try String(contentsOf: fixture.requests, encoding: .utf8)
        #expect(requests.contains("/redirect"))
        #expect(!requests.contains("/capture"))
    }
}

/// Hosts synthetic local HTTP replies to exercise the actual URLSession byte stream.
private final class DecisionHTTPFixture {
    let requests: URL
    private let directory: URL
    private let process: Process
    private let port: Int

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("thread-http-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        requests = directory.appendingPathComponent("requests.txt")
        process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", "-c", Self.server, requests.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch {
            try FileManager.default.removeItem(at: directory)
            throw error
        }
        let line = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let boundPort = Int(line) else {
            process.terminate()
            process.waitUntilExit()
            try FileManager.default.removeItem(at: directory)
            throw RemoteDecisionError.transportUnavailable
        }
        port = boundPort
    }

    func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)/\(path)")! }
    func stop() {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("HTTP fixture cleanup failed") }
    }

    private static let server = """
    from http.server import HTTPServer, BaseHTTPRequestHandler
    import sys
    class Reply(BaseHTTPRequestHandler):
        def log_message(self, *args): pass
        def do_GET(self):
            with open(sys.argv[1], 'a') as records: records.write(self.path + '\\n')
            if self.path == '/redirect':
                self.send_response(307)
                self.send_header('Location', '/capture')
                self.end_headers()
                return
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            try: self.wfile.write(b' ' * 65537 if self.path == '/oversized' else b'{}')
            except (BrokenPipeError, ConnectionResetError): pass
    server = HTTPServer(('127.0.0.1', 0), Reply)
    print(server.server_address[1], flush=True)
    server.serve_forever()
    """
}
