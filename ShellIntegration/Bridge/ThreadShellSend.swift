import Foundation
import ThreadShell

/// Serializes hook arguments as metadata, never as executable shell input.
@main
struct ThreadShellSend {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count == 7, let kind = ShellMessage.Kind(rawValue: arguments[0]),
                  let session = UUID(uuidString: arguments[1]), let pid = Int32(arguments[2]),
                  let sequence = UInt64(arguments[3]) else { throw ShellTransportError.invalidMessage }
            let message = ShellMessage(kind: kind, session: session, processIdentifier: pid,
                                       workingDirectory: arguments[4], terminalApplication: arguments[5].isEmpty ? nil : arguments[5],
                                       sequence: sequence, exitStatus: Int32(arguments[6]))
            let override = ProcessInfo.processInfo.environment["THREAD_SOCKET_PATH"]
            let url = override.map { URL(fileURLWithPath: $0) } ?? ShellSocketLocation.defaultURL
            try ShellMessageSender().send(message, to: url)
        } catch {
            // The hook treats a missing listener as a normal offline state; never print payloads.
            Foundation.exit(1)
        }
    }
}
