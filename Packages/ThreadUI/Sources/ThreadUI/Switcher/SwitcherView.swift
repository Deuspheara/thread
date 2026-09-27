import SwiftUI
import ThreadDomain

/// Renders a quiet launcher with search, selection, an honest preview and keyboard actions.
public struct SwitcherView: View {
    @Bindable private var model: SwitcherModel
    @FocusState private var searching: Bool
    private let restoration: ThreadRestoreModel
    private let details: (ThreadID) -> Void
    private let actions: (ThreadID) -> Void
    private let dismiss: () -> Void
    public init(model: SwitcherModel, restoration: ThreadRestoreModel, details: @escaping (ThreadID) -> Void,
                actions: @escaping (ThreadID) -> Void, dismiss: @escaping () -> Void) {
        self.model = model; self.restoration = restoration; self.details = details; self.actions = actions; self.dismiss = dismiss
    }
    private struct PreviewRequest: Equatable { let thread: ThreadID?; let revision: Int }
    private struct SearchRequest: Equatable { let query: String; let includeArchived: Bool }
    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search your work", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 16)).focused($searching)
                    .onSubmit { activate() }
                    .onKeyPress(.downArrow) { model.move(1); return .handled }
                    .onKeyPress(.upArrow) { model.move(-1); return .handled }
                if !model.query.isEmpty {
                    Toggle("Archived", isOn: $model.includeArchived).toggleStyle(.checkbox).font(.caption)
                        .help("Include archived Threads in search")
                }
            }.padding(.horizontal, 18).frame(height: 49)
            Divider()
            results
            Divider()
            ResumePreview(model: model)
            Divider()
            actionBar
        }
        .frame(width: 620, height: 420)
        .onChange(of: model.focusRequest, initial: true) {
            searching = false
            Task { @MainActor in
                await Task.yield()
                searching = true
            }
        }
        .onExitCommand(perform: dismiss)
        .sheet(isPresented: Binding(get: { restoration.showingOutcomes }, set: { restoration.showingOutcomes = $0 })) {
            ResumeOutcomesView(model: restoration)
        }
        .task(id: SearchRequest(query: model.query, includeArchived: model.includeArchived)) { await model.refresh() }
        .task(id: PreviewRequest(thread: model.selection, revision: model.previewRevision)) { await model.loadPreview() }
    }
    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if model.failed { Text("Saved history search is unavailable. Try again.").foregroundStyle(.secondary).padding(16) }
                    if model.shortcutUnavailable { Text("Option–Space is unavailable. Open Thread from the menu bar.").font(.caption).padding(8) }
                    if model.rows.isEmpty && !model.loading && !model.failed {
                        Text(model.query.isEmpty ? "No recent Threads yet. Your related work will appear here." : "No matching Threads. Try another search or include archived work.")
                            .font(.system(size: 13)).foregroundStyle(.secondary).padding(24)
                    }
                    ForEach(model.rows) { row in
                        Button { model.selection = row.id; activate() } label: {
                            SwitcherRow(row: row, selected: model.selection == row.id, current: model.active == row.id)
                        }.buttonStyle(.plain).id(row.id).disabled(restoration.busy)
                            .contextMenu {
                                Button("Details") { details(row.id) }
                                Button("Actions…") { actions(row.id) }
                            }
                    }
                }.padding(8)
            }
            .overlay(alignment: .topTrailing) {
                if model.loading {
                    ProgressView().controlSize(.small).padding(12)
                        .accessibilityLabel("Searching Threads")
                }
            }
            .onChange(of: model.selection) { if let id = model.selection { proxy.scrollTo(id) } }
        }
        .frame(maxHeight: .infinity)
        .transaction { $0.animation = nil }
    }
    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("Details") { if let id = model.selection { details(id) } }
                .keyboardShortcut("i").buttonStyle(.plain)
                .disabled(model.selection == nil)
            if let message = restoration.message {
                Text(message).lineLimit(1).frame(maxWidth: 260, alignment: .leading).help(message)
            }
            Spacer(minLength: 4)
            if !restoration.items.isEmpty {
                Button("Issues") { restoration.showingOutcomes = true }.buttonStyle(.plain)
            }
            glassActions
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12).frame(height: 48)
    }
    private var glassActions: some View {
        HStack(spacing: 8) {
            Button(action: activate) {
                HStack(spacing: 9) {
                    Text("Resume").fontWeight(.semibold)
                    shortcut("↩")
                }
            }
            .disabled(model.selection == nil || model.loading || restoration.busy)
            .threadActionButton(prominent: true)
            Button { if let id = model.selection { actions(id) } } label: {
                HStack(spacing: 9) {
                    Text("Actions")
                    shortcut("⌘K")
                }
            }
            .keyboardShortcut("k")
            .disabled(model.selection == nil)
            .threadActionButton()
        }
        .threadGlassActionGroup()
    }
    private func shortcut(_ value: String) -> some View {
        Text(value).font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5).frame(height: 18)
            .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }
    private func activate() {
        guard !restoration.busy, !model.loading, let id = model.selection else { return }
        guard let row = model.rows.first(where: { $0.id == id }) else { return }
        if row.isArchived { details(id) }
        else { Task { await restoration.restore(id, title: row.title, plan: model.preview) } }
    }
}
