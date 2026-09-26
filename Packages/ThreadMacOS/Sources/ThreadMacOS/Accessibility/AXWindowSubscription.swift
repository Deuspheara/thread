import ApplicationServices
import Foundation
import OSLog

/// Owns one foreground application's AX registration and focused-window notifications.
@MainActor
final class AXWindowSubscription {
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var window: AXUIElement?
    private let callback: @MainActor (String, AXUIElement) -> Void
    private let logger = Logger(subsystem: "app.thread.desktop", category: "activity")
    private let applicationNotifications = [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification]
    private let windowNotifications = [
        kAXTitleChangedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
        kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification
    ]

    init(callback: @escaping @MainActor (String, AXUIElement) -> Void) {
        self.callback = callback
    }

    func start(processIdentifier: Int32) -> Bool {
        stop()
        var created: AXObserver?
        let result = AXObserverCreate(processIdentifier, { _, element, notification, pointer in
            guard let pointer else { return }
            // Registered only on the main run loop; refcon remains alive until stop removes the source.
            MainActor.assumeIsolated {
                let owner = Unmanaged<AXWindowSubscription>.fromOpaque(pointer).takeUnretainedValue()
                owner.callback(notification as String, element)
            }
        }, &created)
        guard result == .success, let created else {
            logger.error("Could not create focused application observer")
            return false
        }
        observer = created
        let element = AXUIElementCreateApplication(processIdentifier)
        application = element
        AXUIElementSetMessagingTimeout(element, 0.2)
        for name in applicationNotifications { add(name, to: element) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        return true
    }

    func observeWindow(_ element: AXUIElement?) {
        if let window, let element, CFEqual(window, element) { return }
        if let observer, let window {
            for name in windowNotifications { AXObserverRemoveNotification(observer, window, name as CFString) }
        }
        window = element
        if let element {
            for name in windowNotifications { add(name, to: element) }
        }
    }

    isolated deinit { stop() }

    func stop() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observeWindow(nil)
        if let application {
            for name in applicationNotifications { AXObserverRemoveNotification(observer, application, name as CFString) }
        }
        self.observer = nil
        application = nil
    }

    private func add(_ name: String, to element: AXUIElement) {
        guard let observer else { return }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(observer, element, name as CFString, pointer)
        switch result {
        case .success, .notificationAlreadyRegistered, .notificationUnsupported:
            break // Unsupported notifications retain one-shot reads on activation/manual refresh.
        default:
            logger.error("Focused window notification registration failed")
        }
    }
}
