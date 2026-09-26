import SwiftUI

/// Presents explicit application/domain exclusions without exposing activity data.
struct ObservationExclusionsView: View {
    @Bindable var model: ObservationExclusionsModel

    var body: some View {
        Section("Privacy exclusions") {
            Text("Ignored applications (bundle identifiers)").font(.subheadline)
            TextEditor(text: $model.applicationsText).frame(height: 70)
                .accessibilityLabel("Ignored application bundle identifiers")
            Text("Example: com.apple.mail").font(.caption).foregroundStyle(.secondary)
            Text("Ignored browser domains").font(.subheadline)
            TextEditor(text: $model.domainsText).frame(height: 70)
                .accessibilityLabel("Ignored browser domains")
            Text("One domain per line. Subdomains are included. Previously saved history remains.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Save exclusions") { Task { await model.apply() } }
                Button("Reload saved rules") { Task { await model.reload() } }
            }
            .disabled(model.saving)
            if let message = model.message { Text(message).font(.caption) }
        }
    }
}
