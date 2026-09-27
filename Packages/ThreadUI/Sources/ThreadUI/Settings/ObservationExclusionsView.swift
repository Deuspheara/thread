import SwiftUI

/// Presents explicit application/domain exclusions without exposing activity data.
struct ObservationExclusionsView: View {
    @Bindable var model: ObservationExclusionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privacy exclusions").font(.system(size: 12, weight: .semibold))
            Text("Ignored applications (bundle identifiers)").font(.subheadline)
            TextEditor(text: $model.applicationsText).frame(height: 70)
                .accessibilityLabel("Ignored application bundle identifiers")
                .scrollContentBackground(.hidden)
                .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            Text("Example: com.apple.mail").font(.caption).foregroundStyle(.secondary)
            Text("Ignored browser domains").font(.subheadline)
            TextEditor(text: $model.domainsText).frame(height: 70)
                .accessibilityLabel("Ignored browser domains")
                .scrollContentBackground(.hidden)
                .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            Text("One domain per line. Subdomains are included. Previously saved history remains.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Save exclusions") { Task { await model.apply() } }
                    .threadActionButton(prominent: true)
                Button("Reload saved rules") { Task { await model.reload() } }
                    .threadActionButton()
            }
            .disabled(model.saving)
            if let message = model.message { Text(message).font(.caption) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }
}
