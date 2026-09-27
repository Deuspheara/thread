import SwiftUI

/// Explains the limited metadata purpose before forwarding explicit authorization intent.
struct AccessibilityPermissionView: View {
    let request: () -> Void
    let openSettings: () -> Void
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Window access", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
            Text("Optional. Adds window titles and positions. macOS will ask you to approve access in System Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Request Access", action: request)
                    .threadActionButton(prominent: true)
                Button("Open System Settings", action: openSettings)
                    .threadActionButton()
                Button("Check Again", action: refresh)
                    .threadActionButton()
            }
            .threadGlassActionGroup()
            .controlSize(.regular)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
    }
}
