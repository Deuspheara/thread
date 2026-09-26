import SwiftUI

/// Presents optional remote inference consent and independent Thread credential entry.
public struct RemoteInferenceView: View {
    @Bindable private var model: RemoteInferenceModel
    public init(model: RemoteInferenceModel) { self.model = model }

    public var body: some View {
        Section("Remote inference") {
            Toggle("Use remote inference for ambiguous activity", isOn: $model.enabled)
                .disabled(model.busy)
            Text("Changes apply when saved. Stop takes effect immediately.").font(.caption).foregroundStyle(.secondary)
            Text("When enabled, minimized application identifiers, repository/file names, branches and domains go to your Thread backend and OpenRouter. Local matching remains available.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("HTTPS decision endpoint", text: $model.endpointText)
                .disabled(model.busy)
            SecureField("New Thread session token", text: $model.credentialText)
                .disabled(model.busy)
            Text("Leave the token blank to keep the credential for this exact endpoint. Your OpenRouter key belongs on the backend.")
                .font(.caption).foregroundStyle(.secondary)
            if model.credential == .stored { Text("A credential is saved for the loaded endpoint.").font(.caption) }
            if model.credential == .unavailable { Text("Saved credential availability could not be checked.").font(.caption) }
            HStack {
                Button("Save configuration") { Task { await model.apply() } }
                Button("Stop remote inference") { Task { await model.stop() } }
            }.disabled(model.busy)
            HStack {
                Button("Remove credential for saved endpoint", role: .destructive) { Task { await model.removeCredential() } }
                Button("Reload") { Task { await model.reload() } }
            }.disabled(model.busy)
            if let message = model.message { Text(message).font(.caption).accessibilityLabel(message) }
        }
        .task { await model.reload() }
    }
}
