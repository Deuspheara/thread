import SwiftUI
import ThreadDomain

/// Renders the currently observed application and focused-window metadata.
public struct CurrentContextView: View {
    private let model: CurrentContextModel

    public init(model: CurrentContextModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Current Context", systemImage: "square.stack.3d.up")
                    .font(.headline)
                Spacer()
                Button(action: model.refresh) { Image(systemName: "arrow.clockwise") }
                    .help("Refresh context and permissions")
                    .accessibilityLabel("Refresh context")
            }
            ContextFields(context: model.context)
            if model.context.permission != .granted {
                AccessibilityPermissionView(
                    request: model.requestPermission,
                    openSettings: model.openSettings,
                    refresh: model.refresh
                )
            }
            if model.settingsUnavailable {
                Text("Open System Settings → Privacy & Security → Accessibility and enable Thread.")
                    .font(.caption)
            }
            if !model.shellAvailable {
                Text("Shell integration could not start. Another Thread instance may be running. Restart Thread to retry.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.browserAvailable {
                Text("Browser integration could not start. Restart Thread to retry.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            storageStatus
            Text("History stays on this Mac. Remote inference is optional; enabling it in Settings sends minimized metadata to your Thread backend and OpenRouter.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 380, alignment: .leading)
        .onAppear { model.refresh() }
    }

    @ViewBuilder
    private var storageStatus: some View {
        switch model.storage {
        case .preparing:
            ProgressView("Preparing local storage…").controlSize(.small)
        case .ready:
            EmptyView()
        case .unavailable:
            Text("Local storage is unavailable. Observation can continue.")
                .foregroundStyle(.secondary)
            Button("Retry storage") { Task { await model.prepare() } }
        }
    }
}
