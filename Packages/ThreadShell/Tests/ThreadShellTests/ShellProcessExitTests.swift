import Darwin
import Foundation
import Testing
import ThreadDomain
@testable import ThreadShell

struct ShellProcessExitTests {
    @Test(arguments: [false, true]) @MainActor
    func processExitEmitsOneEndAndCannotRevive(killWithoutHook: Bool) async throws {
        let directory = URL(fileURLWithPath: "/private/tmp/tex-" + UUID().uuidString.prefix(8))
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = directory.appendingPathComponent("s.sock")
        let source = ShellActivitySource(url: socket)
        try source.start()
        defer { source.stop() }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        let session = UUID()
        var events: [ActivityEventKind] = []
        let consumer = Task { for await event in source.events() { events.append(event.kind) } }
        defer { consumer.cancel() }
        let sender = ShellMessageSender()
        let initial = ShellMessage(kind: .directory, session: session, processIdentifier: child.processIdentifier,
            workingDirectory: "/tmp/fixture", terminalApplication: nil, sequence: 1)
        try sender.send(initial, to: socket)
        let deadline = Date().addingTimeInterval(2)
        while events.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(events.count == 1)
        if !killWithoutHook {
            try sender.send(ShellMessage(kind: .ended, session: session, processIdentifier: child.processIdentifier,
                workingDirectory: "/tmp/fixture", terminalApplication: nil, sequence: 2), to: socket)
        }
        #expect(kill(child.processIdentifier, SIGKILL) == 0)
        while events.count < 2, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(events.last == .terminalSessionEnded(TerminalSessionIdentity(rawValue: session)))
        let delayed = ShellMessage(kind: .directory, session: session, processIdentifier: child.processIdentifier,
            workingDirectory: "/tmp/fixture", terminalApplication: nil, sequence: 3)
        try sender.send(delayed, to: socket)
        try await Task.sleep(for: .milliseconds(20))
        #expect(events.count == 2)
        child.waitUntilExit()
        source.stop()
        await consumer.value
    }
}
