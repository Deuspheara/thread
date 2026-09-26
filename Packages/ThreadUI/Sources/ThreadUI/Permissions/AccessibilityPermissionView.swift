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
            Text("Allow Accessibility access to read the focused window’s title and position. Application observation works without it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Allow access", action: request)
                Button("Settings…", action: openSettings)
                Button("Check again", action: refresh)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}
