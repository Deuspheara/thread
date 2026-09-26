import AppKit
import SwiftUI

/// Owns the transient native switcher panel and dismisses it when focus leaves.
@MainActor
public final class SwitcherPanel: NSObject, NSWindowDelegate {
    private let model: SwitcherModel
    private let detail: ThreadDetailModel
    private let restoration: ThreadRestoreModel
    private var panel: NSPanel?

    public init(model: SwitcherModel, detail: ThreadDetailModel, restoration: ThreadRestoreModel) {
        self.model = model
        self.detail = detail
        self.restoration = restoration
    }

    public func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    public func show() {
        if panel?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            panel?.makeKeyAndOrderFront(nil)
            return
        }
        model.reset()
        if panel == nil { createPanel() }
        installContent()
        panel?.center()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    public func close() {
        guard let closing = panel else { return }
        panel = nil
        closing.delegate = nil
        closing.orderOut(nil)
        // Hidden relative-date Text views otherwise keep scheduling layout work.
        closing.contentView = nil
    }

    public func windowDidResignKey(_ notification: Notification) {
        guard !detail.presented, let window = notification.object as? NSWindow,
              window === panel, window.attachedSheet == nil else { return }
        close()
    }

    private func createPanel() {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                             styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Thread"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        self.panel = panel
    }
    private func installContent() {
        panel?.contentView = NSHostingView(rootView: PanelContent(
            model: model, detail: detail, restoration: restoration,
            dismiss: { [weak self] in self?.close() }))
    }
}

@MainActor
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct PanelContent: View {
    let model: SwitcherModel
    @Bindable var detail: ThreadDetailModel
    let restoration: ThreadRestoreModel
    let dismiss: () -> Void

    var body: some View {
        SwitcherView(model: model, restoration: restoration, details: detail.open, dismiss: dismiss)
            .sheet(isPresented: $detail.presented, onDismiss: { Task { await model.refresh() } }) {
                ThreadDetailView(model: detail)
            }
    }
}
