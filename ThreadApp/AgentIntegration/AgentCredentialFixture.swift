#if DEBUG
import Foundation
import Darwin
import ThreadDomain
import ThreadAgentTransport

/// Exercises fictional credentials through the signed helper without observation or remote requests.
enum AgentCredentialFixture {
    @MainActor static func runIfRequested() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment["THREAD_AGENT_CREDENTIAL_CHECK"] == "1" else { return false }
        guard let path = environment["THREAD_DATA_DIRECTORY"], let directory = ownedDirectory(path) else { exit(78) }
        Task {
            let client = AgentConnection(app: Bundle.main.bundleURL)
            var stage = "configure"
            var configured = false
            do {
                guard case .done = try await client.request(.configure(debugDirectory: directory.path)) else {
                    throw AgentTransportError.invalidMessage
                }
                configured = true
                let endpoint = URL(string: "https://\(UUID().uuidString.lowercased()).example/v1/decisions")!
                let preferences = try RemoteInferencePreferences(enabled: false, endpoint: endpoint)
                // Save the scope first so cleanup can remove an item even if the credential save fails.
                guard case .done = try await client.request(.remoteApply(preferences, token: nil)) else {
                    throw AgentTransportError.invalidMessage
                }
                stage = "save"
                guard case .done = try await client.request(.remoteApply(preferences, token: String(repeating: "a", count: 43))) else {
                    throw AgentTransportError.invalidMessage
                }
                stage = "read"
                guard case .remote(let state) = try await client.request(.remoteState), state.credential == .stored else {
                    throw AgentTransportError.invalidMessage
                }
                stage = "passed"
            } catch { /* Only a fixed stage is written; the helper logs bounded numeric Security failures. */ }
            if configured {
                do {
                    guard case .done = try await client.request(.remoteForget) else { throw AgentTransportError.invalidMessage }
                    guard case .remote(let state) = try await client.request(.remoteState), state.credential == .notStored else {
                        throw AgentTransportError.invalidMessage
                    }
                } catch { stage = "cleanup-failed" }
                do { try await client.shutdownIfConnected() }
                catch { stage = "shutdown-failed" }
            }
            await client.close()
            do {
                let result = directory.appendingPathComponent("AgentCredentialResult")
                try Data(stage.utf8).write(to: result, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: result.path)
            } catch { exit(74) }
            exit(stage == "passed" ? 0 : 1)
        }
        return true
    }

    private static func ownedDirectory(_ path: String) -> URL? {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let parent = url.deletingLastPathComponent()
        guard url.lastPathComponent == "data", parent.lastPathComponent.hasPrefix("th-agent-credential-"),
              ["/private/tmp", "/tmp"].contains(parent.deletingLastPathComponent().path) else { return nil }
        for directory in [parent, url] {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path),
                  attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else { return nil }
        }
        return url
    }
}
#endif
