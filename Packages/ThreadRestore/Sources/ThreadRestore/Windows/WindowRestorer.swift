import AppKit
import ApplicationServices
import ThreadDomain

/// Raises a uniquely matched surviving window and restores supported geometry.
public struct WindowRestorer: ResourceRestorer {
    public init() {}

    @MainActor public func capability(for resource: Resource) async -> RestoreCapability {
        guard case .window(let context) = resource, match(context) != nil else { return .unavailable }
        return context.frame == nil ? .activateOnly : .partial
    }

    @MainActor public func restore(_ resource: Resource) async throws -> RestoreResult {
        guard case .window(let context) = resource, let window = match(context) else {
            return RestoreResult(resource: resource.id, capability: .unavailable, outcome: .unavailable)
        }
        try Task.checkCancellation()
        let raised = AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
        let moved = restoreFrame(context.frame, window: window)
        let capability: RestoreCapability = moved ? .partial : .activateOnly
        return RestoreResult(resource: resource.id, capability: capability, outcome: raised || moved ? .restored : .failed)
    }

    @MainActor private func match(_ context: WindowContext) -> AXUIElement? {
        guard AXIsProcessTrusted(), let title = context.title, !title.isEmpty,
              let launch = context.application.launchDate,
              let app = NSRunningApplication(processIdentifier: context.application.processIdentifier),
              app.bundleIdentifier == context.application.identity.bundleIdentifier, app.launchDate == launch else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement], windows.count <= 32 else { return nil }
        let matching = windows.filter { window in
            AXUIElementSetMessagingTimeout(window, 0.1)
            var titleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
                  let current = titleValue as? String else { return false }
            return String(current.prefix(512)) == title
        }
        return matching.count == 1 ? matching.first : nil
    }

    @MainActor private func restoreFrame(_ saved: WindowFrame?, window: AXUIElement) -> Bool {
        guard let saved, let primary = NSScreen.screens.first else { return false }
        let screens = NSScreen.screens.map { screen in
            let frame = screen.visibleFrame
            return WindowFrame(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        }
        guard let frame = WindowGeometry().frame(saved, screens: screens) else { return false }
        var point = CGPoint(x: frame.x, y: frame.y), size = CGSize(width: frame.width, height: frame.height)
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else { return false }
        let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions) == .success
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success
        return resized || moved
    }
}
