import ApplicationServices
import Foundation
import ThreadDomain

/// Reads only a focused window's title and geometry with a bounded AX messaging timeout.
@MainActor
struct FocusedWindowReader {
    enum Result {
        case window(AXUIElement, WindowContext)
        case unavailable(WindowAvailability)
    }

    let identities: WindowIdentityRegistry
    let titlePolicy: WindowTitlePolicy

    func read(application: ApplicationContext) -> Result {
        let element = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.2)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return .unavailable(availability(for: result))
        }
        let window = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(window, 0.2)
        let context = WindowContext(
            identity: identities.identity(for: window, application: application),
            application: application,
            title: titlePolicy.permitsTitle(for: application) ? title(of: window) : nil,
            frame: frame(of: window),
            document: titlePolicy.permitsTitle(for: application)
                ? LocalDocumentIdentity().file(attribute(window, kAXDocumentAttribute) as? String) : nil
        )
        return .window(window, context)
    }

    private func title(of window: AXUIElement) -> String? {
        guard let value = attribute(window, kAXTitleAttribute) as? String else { return nil }
        return String(value.prefix(512))
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func frame(of window: AXUIElement) -> WindowFrame? {
        guard let position = attribute(window, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(window, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        let positionValue = unsafeDowncast(position, to: AXValue.self)
        let sizeValue = unsafeDowncast(size, to: AXValue.self)
        guard AXValueGetType(positionValue) == .cgPoint, AXValueGetType(sizeValue) == .cgSize else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite else { return nil }
        return WindowFrame(x: point.x, y: point.y, width: dimensions.width, height: dimensions.height)
    }

    private func availability(for error: AXError) -> WindowAvailability {
        switch error {
        case .success, .noValue: .noFocusedWindow
        case .apiDisabled: .permissionRequired
        case .attributeUnsupported, .notImplemented: .unsupported
        default: .temporarilyUnavailable
        }
    }
}
