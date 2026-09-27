import AppKit
import SwiftUI

/// Gives utility panels the switcher's rounded native material surface.
struct ThreadPanelSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
                else { Rectangle().fill(.regularMaterial) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.primary.opacity(contrast == .increased ? 0.55 : 0.12), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                WindowDragRegion().frame(height: 12)
                    .background(alignment: .center) {
                        Capsule().fill(Color.primary.opacity(0.24)).frame(width: 34, height: 3)
                    }
            }
    }
}

/// Exposes a visible drag handle above the controls of each borderless panel.
private struct WindowDragRegion: View {
    @ViewBuilder var body: some View {
        if #available(macOS 15, *) {
            Color.clear.contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents()
        } else {
            AppKitWindowDragRegion()
        }
    }
}

/// Starts a native window drag on macOS 14, before WindowDragGesture existed.
private struct AppKitWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

extension View {
    func threadPanelSurface() -> some View { modifier(ThreadPanelSurface()) }
}

/// Lets borderless setup and settings panels receive keyboard focus.
@MainActor final class ThreadUtilityPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
