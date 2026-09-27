import AppKit
import SwiftUI
import ThreadDomain

/// Resolves application icons locally, retaining a native fallback for missing applications.
struct ApplicationIcon: View {
    let application: WorkApplication
    var size: CGFloat = 28
    @State private var icon: NSImage?
    var body: some View {
        Group {
            if let icon { Image(nsImage: icon).resizable() }
            else { Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary).padding(3) }
        }
        .frame(width: size, height: size)
        .help(application.name).accessibilityHidden(true)
        .task(id: application.id) {
            if let bundle = application.identity?.bundleIdentifier,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                icon = NSWorkspace.shared.icon(forFile: url.path)
            } else { icon = nil }
        }
    }
}

/// Shows at most three app icons without displacing the Thread title.
struct ApplicationIconCluster: View {
    let applications: [WorkApplication]
    var body: some View {
        HStack(spacing: -3) {
            ForEach(Array(applications.prefix(3).enumerated()), id: \.element.id) { index, app in
                ApplicationIcon(application: app, size: index == 0 ? 28 : 19)
            }
            if applications.count > 3 { Text("+\(applications.count - 3)").font(.system(size: 9)).foregroundStyle(.secondary) }
            if applications.isEmpty { Image(systemName: "square.stack").foregroundStyle(.secondary).frame(width: 28) }
        }
        .frame(width: 72, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(applications.map(\.name).joined(separator: ", "))
    }
}
