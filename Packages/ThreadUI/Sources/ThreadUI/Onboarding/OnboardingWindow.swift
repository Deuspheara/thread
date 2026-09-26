import AppKit
import SwiftUI

/// Owns a reopenable setup window independently of menu and switcher visibility.
@MainActor
public final class OnboardingWindow: NSWindowController, NSWindowDelegate {
    private let model: OnboardingModel

    public init(model: OnboardingModel) {
        self.model = model
        super.init(window: nil)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Welcome to Thread"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: OnboardingView(model: model, close: { [weak self] in self?.close() }))
        self.window = window
    }

    public required init?(coder: NSCoder) { return nil }

    public func present() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    public func windowDidBecomeKey(_ notification: Notification) { model.refreshPermission() }
}
