import SwiftUI
import ThreadDomain

/// Renders the compact keyboard-first Thread picker.
public struct SwitcherView: View {
    @Bindable private var model: SwitcherModel
    @FocusState private var searching: Bool
    private let restoration: ThreadRestoreModel
    private let details: (ThreadID) -> Void
    private let dismiss: () -> Void

    public init(model: SwitcherModel, restoration: ThreadRestoreModel, details: @escaping (ThreadID) -> Void, dismiss: @escaping () -> Void) {
        self.model = model; self.restoration = restoration; self.details = details; self.dismiss = dismiss
    }

    private struct SearchRequest: Equatable {
        let query: String
        let includeArchived: Bool
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Threads").font(.title2.weight(.semibold))
            TextField("Search your work", text: $model.query)
                .textFieldStyle(.plain).font(.title3).focused($searching)
                .onSubmit { activate() }
                .onKeyPress(.downArrow) { model.move(1); return .handled }
                .onKeyPress(.upArrow) { model.move(-1); return .handled }
                .onKeyPress(.escape) { dismiss(); return .handled }
            if !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Toggle("Include archived", isOn: $model.includeArchived)
            }
            Divider()
            if model.loading { ProgressView().controlSize(.small) }
            if model.failed { Text("Saved history search is unavailable.").foregroundStyle(.secondary) }
            if !model.loading && !model.failed && model.rows.isEmpty {
                Text(emptyMessage).foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.rows) { row in
                            Button { model.selection = row.id; activate() } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        if row.isPinned { Image(systemName: "pin.fill").accessibilityLabel("Pinned Thread") }
                                        Text(row.title).font(.headline).lineLimit(1)
                                    }
                                    HStack {
                                        Text(row.lastActive, style: .relative)
                                        Text("· \(row.resourceCount) resources")
                                        if row.isArchived { Text("· Archived") }
                                    }.font(.caption).foregroundStyle(.secondary)
                                    if !row.applications.isEmpty {
                                        Text(row.applications).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(row.id == model.selection ? Color.accentColor.opacity(0.15) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).id(row.id)
                            .disabled(restoration.busy)
                            .contextMenu { Button("Details") { details(row.id) } }
                        }
                    }
                }
                .onChange(of: model.selection) { if let id = model.selection { proxy.scrollTo(id) } }
            }
            if let message = restoration.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            Text("Directories reopen in Terminal. Commands are never replayed.").font(.caption2).foregroundStyle(.secondary)
            Text("↑ ↓ Select    ↩ Continue    esc Close").font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 520, height: 460)
        .onAppear { searching = true }
        .onExitCommand(perform: dismiss)
        .task(id: SearchRequest(query: model.query, includeArchived: model.includeArchived)) { await model.refresh() }
    }

    private var emptyMessage: String {
        if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No recent Threads. Work across related resources to build your context."
        }
        return model.includeArchived ? "No matching Threads. Try another search."
            : "No matching Threads. Try another search or include archived work."
    }

    private func activate() {
        guard !restoration.busy, let id = model.selection else { return }
        if model.rows.first(where: { $0.id == id })?.isArchived == true {
            details(id)
        } else {
            Task { await restoration.restore(id) }
        }
    }
}
