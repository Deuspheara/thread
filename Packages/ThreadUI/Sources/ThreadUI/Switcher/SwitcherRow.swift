import SwiftUI
import ThreadDomain

/// Presents a Thread's apps and useful work anchor with distinct current and selected states.
struct SwitcherRow: View {
    let row: SwitcherModel.Row
    let selected: Bool
    let current: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        HStack(spacing: 10) {
            ApplicationIconCluster(applications: row.work?.applications ?? [])
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(row.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if row.isPinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.secondary) }
                }
                Text(context).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if current {
                Label("Current", systemImage: "circle.inset.filled").font(.system(size: 10, weight: .medium))
            } else if row.isArchived {
                Text("Archived").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text(row.lastActive, style: .relative).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 10).frame(height: 57)
        .background(selected ? Color.primary.opacity(contrast == .increased ? 0.18 : 0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            if selected && contrast == .increased { RoundedRectangle(cornerRadius: 6).stroke(Color.primary, lineWidth: 1) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selected ? "Selected" : "")
    }
    private var accessibilityLabel: String {
        let apps = row.work?.applications.map(\.name).joined(separator: ", ") ?? row.applications
        let lastActive = row.lastActive.formatted(date: .abbreviated, time: .shortened)
        return [row.title, apps, row.work?.context ?? "", current ? "Current Thread" : "",
                row.isPinned ? "Pinned" : "", row.isArchived ? "Archived" : "", "Last active \(lastActive)"]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }
    private var context: String {
        if let work = row.work, !work.context.isEmpty { return work.context }
        return row.applications.isEmpty ? "Saved work" : row.applications
    }
}
