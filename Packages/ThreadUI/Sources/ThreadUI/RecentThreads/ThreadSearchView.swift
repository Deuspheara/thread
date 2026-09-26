import SwiftUI
import ThreadDomain

/// Renders searchable saved history and forwards query changes to its presentation model.
public struct ThreadSearchView: View {
    @Bindable private var model: ThreadSearchModel
    private let open: (ThreadID) -> Void
    public init(model: ThreadSearchModel, open: @escaping (ThreadID) -> Void) { self.model = model; self.open = open }

    private struct SearchRequest: Equatable {
        let query: String
        let includeArchived: Bool
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search saved Threads", text: $model.query)
                .textFieldStyle(.roundedBorder)
            if !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Toggle("Include archived", isOn: $model.includeArchived)
                if model.isLoading {
                    ProgressView().controlSize(.small)
                } else if model.failed {
                    Text("Search is unavailable. Retry storage in Observed context.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Retry search") { Task { await model.refresh() } }
                } else if model.results.isEmpty {
                    Text("No saved Threads match.").foregroundStyle(.secondary)
                }
                ForEach(model.results) { result in
                    Button { open(result.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title).font(.callout.weight(.medium))
                        Text("\(result.resourceCount) resources\(result.isArchived ? " · Archived" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 16)
        .frame(width: 380, alignment: .leading)
        .task(id: SearchRequest(query: model.query, includeArchived: model.includeArchived)) { await model.refresh() }
    }
}
