import AppKit
import SwiftUI
import ThreadDomain

/// Owns launcher focus and native panel geometry without changing the global shortcut.
@MainActor
public final class SwitcherPanel: NSObject, NSWindowDelegate {
    private let model: SwitcherModel
    private let detail: ThreadDetailModel
    private let restoration: ThreadRestoreModel
    private var panel: NSPanel?
    private var lastOrigin: NSPoint?
    private var overlayPresented = false
    public init(model: SwitcherModel, detail: ThreadDetailModel, restoration: ThreadRestoreModel) {
        self.model = model; self.detail = detail; self.restoration = restoration
    }
    public func toggle() { if panel?.isVisible == true { close() } else { show() } }
    public func show() {
        if panel?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            panel?.makeKeyAndOrderFront(nil)
            model.focusRequest += 1
            return
        }
        model.reset()
        detail.presented = false
        if panel == nil { createPanel() }
        installContent()
        if let lastOrigin { panel?.setFrameOrigin(lastOrigin) }
        else { panel?.center() }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        model.focusRequest += 1
    }
    public func close() {
        guard let closing = panel else { return }
        lastOrigin = closing.frame.origin
        panel = nil
        overlayPresented = false
        detail.observingActions = false
        closing.delegate = nil
        closing.orderOut(nil)
        closing.contentView = nil
    }
    public func windowDidBecomeKey(_ notification: Notification) {
        model.focusRequest += 1
    }
    public func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel, window.attachedSheet == nil,
              !detail.choosingApplication, !overlayPresented else { return }
        close()
    }
    private func createPanel() {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        panel.cancel = { [weak self] in
            guard let self, !self.overlayPresented, !self.detail.choosingApplication else { return }
            if self.detail.presented { self.detail.presented = false } else { self.close() }
        }
        panel.title = "Thread"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        self.panel = panel
    }
    private func resize(_ expanded: Bool) {
        guard let panel else { return }
        let size = NSSize(width: expanded ? 700 : 620, height: expanded ? 550 : 420)
        let frame = panel.frame
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }
    private func installContent() {
        panel?.contentView = NSHostingView(rootView: PanelContent(model: model, detail: detail, restoration: restoration,
            dismiss: { [weak self] in self?.close() }, resize: { [weak self] in self?.resize($0) },
            overlay: { [weak self] in self?.overlayPresented = $0 }))
    }
}

/// Allows keyboard focus for a borderless native launcher.
@MainActor private final class KeyPanel: NSPanel {
    var cancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { cancel?() }
}

/// Keeps switcher, expanded details and actions on one accessible native material surface.
private struct PanelContent: View {
    let model: SwitcherModel
    @Bindable var detail: ThreadDetailModel
    @Bindable var restoration: ThreadRestoreModel
    let dismiss: () -> Void
    let resize: (Bool) -> Void
    let overlay: (Bool) -> Void
    @State private var showingActions = false
    var body: some View {
        Group {
            if detail.presented {
                ThreadDetailView(model: detail, restoration: restoration, actions: { showingActions = true })
            } else {
                SwitcherView(model: model, restoration: restoration, details: detail.open,
                    actions: { id in detail.prepareActions(id); showingActions = true }, dismiss: dismiss)
            }
        }
        .threadPanelSurface()
        .onChange(of: detail.presented) { resize(detail.presented) }
        .onChange(of: showingActions) {
            detail.observingActions = showingActions
            overlay(showingActions || restoration.showingOutcomes)
        }
        .onChange(of: restoration.showingOutcomes) { overlay(showingActions || restoration.showingOutcomes) }
        .popover(isPresented: $showingActions) {
            ThreadActionPanel(model: detail, restoration: restoration, dismiss: { showingActions = false },
                details: { if let id = detail.selectedID { detail.open(id) } })
        }

    }
}
