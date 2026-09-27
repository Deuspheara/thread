import SwiftUI

/// Gives Thread actions a capsule surface and a visible pointer response.
private struct ThreadActionButtonStyle: ButtonStyle {
    let prominent: Bool

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        ThreadActionButtonBody(configuration: configuration, prominent: prominent)
    }
}

/// Tracks hover per button so the glass reacts independently within a group.
private struct ThreadActionButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let label = configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 15)
            .frame(minHeight: 32)
            .contentShape(Capsule())
        Group {
            if #available(macOS 26, *) {
                label.glassEffect(
                    .regular.tint(prominent ? Color.accentColor.opacity(hovering ? 0.9 : 0.65) :
                        (hovering ? Color.primary.opacity(0.18) : nil)).interactive(isEnabled),
                    in: .capsule
                )
            } else {
                label.background(
                    prominent ? Color.accentColor.opacity(hovering ? 0.9 : 0.75) :
                        Color(nsColor: .controlColor).opacity(hovering ? 0.9 : 0.65),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(.white.opacity(hovering ? 0.3 : 0.15)))
            }
        }
        .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.45)
        .onHover { hovering = $0 }
    }
}

extension View {
    func threadActionButton(prominent: Bool = false) -> some View {
        self.buttonStyle(ThreadActionButtonStyle(prominent: prominent))
    }

    @ViewBuilder
    func threadGlassActionGroup() -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 8) { self }
        } else {
            self
        }
    }
}
