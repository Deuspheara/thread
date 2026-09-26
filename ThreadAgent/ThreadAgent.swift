import Foundation
import Darwin
import OSLog
import ThreadAgentTransport

@main
enum ThreadAgent {
    @MainActor static func main() {
        let bundle = Bundle.main.bundleURL
        let app = bundle.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        do {
            guard bundle.pathExtension == "xpc", app.pathExtension == "app" else { throw AgentProbeError.signatureUnavailable }
            let listener = NSXPCListener.service()
            guard let appBundle = Bundle(url: app) else { throw AgentProbeError.signatureUnavailable }
            let session = AgentCommandSession(appBundle: appBundle)
            let delegate = AgentListener(requirement: try AgentSigningRequirement.string(for: app), session: session)
            Logger(subsystem: "app.thread.desktop", category: "agent").notice("Agent listener trust configured")
            listener.delegate = delegate
            withExtendedLifetime(delegate) { listener.resume() }
        } catch {
            Logger(subsystem: "app.thread.desktop", category: "agent").error("Agent trust setup unavailable")
            exit(78)
        }
    }
}
