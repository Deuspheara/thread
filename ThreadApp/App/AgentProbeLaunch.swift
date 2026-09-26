import AppKit
import Foundation
import Darwin
import OSLog
import ThreadAgentTransport

/// Runs a debug-only owned XPC readiness fixture before observation is authorized or started.
@MainActor
enum AgentProbeLaunch {
    static func runIfRequested() -> Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard environment["THREAD_AGENT_PROBE"] == "1" else { return false }
        guard let path = environment["THREAD_DATA_DIRECTORY"], path.hasPrefix("/private/tmp/th-agent-"),
              isFixturePath(URL(fileURLWithPath: path).resolvingSymlinksInPath().path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else {
            Logger(subsystem: "app.thread.desktop", category: "agent").error("Agent fixture directory rejected")
            exit(78)
        }
        let reject = environment["THREAD_AGENT_PROBE_REJECT"] == "1"
        Logger(subsystem: "app.thread.desktop", category: "agent").notice("Agent fixture requested")
        Task {
            let client = AgentConnection(app: Bundle.main.bundleURL)
            let outcome: Outcome
            do {
                let reply = try await (reject ? client.probeRejectingPeer() : client.probe())
                outcome = Outcome(status: reply.processIdentifier != getpid() && !reject ? .ready : .failed,
                                  agent: reply.processIdentifier)
            } catch AgentTransportError.unavailable {
                outcome = Outcome(status: reject ? .rejected : .failed, agent: nil)
            } catch { outcome = Outcome(status: .failed, agent: nil) }
            await client.close()
            Logger(subsystem: "app.thread.desktop", category: "agent").notice("Agent fixture exchange finished")
            do {
                let file = URL(fileURLWithPath: path).appendingPathComponent("AgentProbeResult.json")
                try JSONEncoder().encode(outcome).write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            } catch {
                Logger(subsystem: "app.thread.desktop", category: "agent").error("Agent fixture result unavailable")
            }
            // This fixture never starts the runtime; the XPC connection was explicitly closed.
            exit(0)
        }
        return true
        #else
        return false
        #endif
    }

    private enum Status: String, Codable { case ready, rejected, failed }
    private struct Outcome: Codable { let status: Status; let agent: Int32? }

    private static func isFixturePath(_ path: String) -> Bool {
        path.hasPrefix("/private/tmp/th-agent-") || path.hasPrefix("/tmp/th-agent-")
    }
}
