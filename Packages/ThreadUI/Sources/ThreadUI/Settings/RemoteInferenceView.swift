import SwiftUI

/// Presents optional remote inference consent and independent Thread credential entry.
public struct RemoteInferenceView: View {
    @Bindable private var model: RemoteInferenceModel
    public init(model: RemoteInferenceModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remote inference").font(.system(size: 12, weight: .semibold))
            Toggle("Use remote inference for ambiguous activity", isOn: $model.enabled)
                .toggleStyle(.switch)
                .tint(Color(red: 0.65, green: 0.34, blue: 0.68))
                .disabled(model.busy)
            Text("Optional. Thread works offline without this. When enabled, minimized app and work labels go to your Thread backend and OpenRouter.")
                .font(.caption).foregroundStyle(.secondary)
            if model.enabled {
                TextField("HTTPS decision endpoint", text: $model.endpointText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.busy)
                SecureField("Thread session token", text: $model.credentialText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.busy)
                Text("Leave the token blank to keep the saved credential for this endpoint. The provider key stays on your backend.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.credential == .stored { Label("Credential saved", systemImage: "checkmark.circle").font(.caption) }
                if model.credential == .unavailable { Text("Saved credential availability could not be checked.").font(.caption) }
                Button("Save and enable") { Task { await model.apply() } }
                    .threadActionButton(prominent: true).disabled(model.busy)
            } else if model.savedEnabled {
                Button("Stop remote inference") { Task { await model.stop() } }
                    .threadActionButton().disabled(model.busy)
            }
            DisclosureGroup("Credential and connection options") {
                HStack {
                    Button("Remove saved credential", role: .destructive) { Task { await model.removeCredential() } }
                        .threadActionButton()
                    Button("Reload settings") { Task { await model.reload() } }
                        .threadActionButton()
                }.disabled(model.busy)
            }
            if let message = model.message { Text(message).font(.caption).accessibilityLabel(message) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .task { await model.reload() }
    }
}
