import SwiftUI
import ThreadDomain

/// Displays the first inferred work contexts while durable history and restoration are developed.
public struct RecentThreadsView: View {
    private let model: RecentThreadsModel
    private let open: (ThreadDomain.ThreadID) -> Void
    public init(model: RecentThreadsModel, open: @escaping (ThreadDomain.ThreadID) -> Void) { self.model = model; self.open = open }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Inferred Threads").font(.headline)
            if model.rows.isEmpty {
                Text("Work in a repository or revisit related resources. Threads appear as context becomes clear.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.rows) { row in
                Button { open(row.id) } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.isActive ? "circle.fill" : "circle")
                        .font(.caption).foregroundStyle(row.isActive ? Color.accentColor : Color.secondary)
                        .accessibilityLabel(row.isActive ? "Active Thread" : "Recent Thread")
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if row.isPinned { Image(systemName: "pin.fill").accessibilityLabel("Pinned Thread") }
                            Text(row.title).font(.callout.weight(.medium)).lineLimit(2)
                        }
                        HStack(spacing: 4) {
                            Text("\(row.resourceCount) resources ·")
                            Text(row.lastActive, style: .relative)
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                }.buttonStyle(.plain)
            }
            if model.unavailable {
                Text("Some activity could not be classified. Observation continues.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(historyLabel).font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 380, alignment: .leading)
    }
    private var historyLabel: String {
        switch model.history {
        case .sessionOnly: "Local · Kept for this session"
        case .loading: "Loading local history…"
        case .saved: "Saved on this Mac"
        case .unavailable: "History unavailable. Retry storage in Observed context."
        case .unsaved: "Recent changes are not saved. Retry storage in Observed context."
        }
    }

}
