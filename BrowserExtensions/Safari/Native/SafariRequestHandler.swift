import Foundation
import OSLog
import SafariServices
import ThreadBrowser

/// Translates Safari extension requests into validated metadata for the shared group socket.
@objc(SafariRequestHandler)
public final class SafariRequestHandler: NSObject, NSExtensionRequestHandling {
    public func beginRequest(with context: NSExtensionContext) {
        let response = NSExtensionItem()
        do {
            let data = try payload(context)
            struct Kind: Decodable { let kind: String }
            if try JSONDecoder().decode(Kind.self, from: data).kind == "restoreResult" {
                let reply = try forwarder().forwardRestoreReply(data)
                response.userInfo = [SFExtensionMessageKey: ["id": reply.id, "accepted": true]]
            } else {
                let reply = try forwarder().forward(data)
                response.userInfo = [SFExtensionMessageKey: try JSONSerialization.jsonObject(with: JSONEncoder().encode(reply))]
            }
        } catch {
            Logger(subsystem: "app.thread.desktop", category: "browser").error("Safari request could not be forwarded")
            response.userInfo = [SFExtensionMessageKey: ["forwarded": false]]
        }
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    private func payload(_ context: NSExtensionContext) throws -> Data {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let message = item.userInfo?[SFExtensionMessageKey], JSONSerialization.isValidJSONObject(message) else {
            throw BrowserTransportError.invalidMessage
        }
        return try JSONSerialization.data(withJSONObject: message)
    }

    private func forwarder() throws -> SafariRequestForwarder {
        guard let group = Bundle(for: Self.self).object(forInfoDictionaryKey: "ThreadAppGroupIdentifier") as? String,
              !group.isEmpty else { throw BrowserTransportError.unavailable }
        return SafariRequestForwarder(endpoint: try BrowserSocketLocation.safariURL(groupIdentifier: group))
    }
}
