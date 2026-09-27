import AppKit
import SwiftUI

/// Owns the reopenable settings panel without relying on the system Form window.
@MainActor
public final class SettingsWindow: NSWindowController {
    private var hasPositioned = false
    public init(login: LoginLaunchModel, exclusions: ObservationExclusionsModel,
                remote: RemoteInferenceModel) {
        super.init(window: nil)
        let window = ThreadUtilityPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 610),
                                        styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Thread Settings"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(login: login, exclusions: exclusions,
            remote: remote, close: { [weak self] in self?.close() }))
        self.window = window
    }

    public required init?(coder: NSCoder) { return nil }

    public func present() {
        if !hasPositioned { window?.center(); hasPositioned = true }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
