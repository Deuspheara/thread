import Darwin
import Foundation
import Testing
@testable import ThreadShell

struct UnixDatagramTests {
    @Test @MainActor func realDatagramRoundTripAndExclusiveLease() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/tsh-" + UUID().uuidString.prefix(8))
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("s.sock")
        var received: Data?
        let listener = UnixDatagramListener { received = $0 }
        try listener.start(at: url)
        defer { listener.stop() }
        let second = UnixDatagramListener { _ in }
        #expect(throws: (any Error).self) { try second.start(at: url) }
        let message = ShellMessage(kind: .directory, session: UUID(), processIdentifier: 1, workingDirectory: "/tmp/project",
                                   terminalApplication: nil, sequence: 1)
        try ShellMessageSender().send(message, to: url)
        let deadline = Date().addingTimeInterval(2)
        while received == nil, Date() < deadline { CFRunLoopRunInMode(.defaultMode, 0.02, true) }
        let decoded = try JSONDecoder().decode(ShellMessage.self, from: #require(received))
        #expect(decoded.session == message.session)
        #expect(decoded.workingDirectory == message.workingDirectory)
        var info = stat()
        #expect(lstat(url.path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o600)
        listener.stop()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try second.start(at: url)
        second.stop()
    }

    @Test @MainActor func refusesUnsafeDirectoryAndNeverDeletesRegularFile() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/tsh-" + UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("s.sock")
        try Data("preserve".utf8).write(to: url)
        let listener = UnixDatagramListener { _ in }
        #expect(throws: (any Error).self) { try listener.start(at: url) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "preserve")
        try FileManager.default.removeItem(at: url)
        chmod(directory.path, 0o755)
        #expect(throws: (any Error).self) { try listener.start(at: url) }
    }
}
