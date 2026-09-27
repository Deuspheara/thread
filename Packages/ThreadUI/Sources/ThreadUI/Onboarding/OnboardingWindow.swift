import AppKit
import SwiftUI

/// Owns a reopenable setup window independently of menu and switcher visibility.
@MainActor
public final class OnboardingWindow: NSWindowController, NSWindowDelegate {
    private let model: OnboardingModel
    private var hasPositioned = false

    public init(model: OnboardingModel, showSettings: @escaping @MainActor () -> Void) {
        self.model = model
        super.init(window: nil)
        let window = ThreadUtilityPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 570),
                                        styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Welcome to Thread"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: OnboardingView(model: model,
            close: { [weak self] in self?.close() }, showSettings: showSettings))
        self.window = window
    }

    public required init?(coder: NSCoder) { return nil }

    public func present() {
        if !hasPositioned { window?.center(); hasPositioned = true }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    public func windowDidBecomeKey(_ notification: Notification) { model.refreshPermission() }
}
