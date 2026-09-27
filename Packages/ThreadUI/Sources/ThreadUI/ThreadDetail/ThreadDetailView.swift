import SwiftUI
import ThreadDomain

/// Presents application-grouped resume destinations inside the native launcher.
public struct ThreadDetailView: View {
    @Bindable private var model: ThreadDetailModel
    private let restoration: ThreadRestoreModel?
    private let actions: (() -> Void)?
    @State private var showingActions = false
    public init(model: ThreadDetailModel, restoration: ThreadRestoreModel? = nil, actions: (() -> Void)? = nil) {
        self.model = model; self.restoration = restoration; self.actions = actions
    }
    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.loading { ProgressView().controlSize(.small) }
                    ForEach(model.groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                ApplicationIcon(application: group.application)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.application.name).font(.system(size: 14, weight: .semibold))
                                    Text(group.description).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu {
                                    ForEach(group.targets, id: \.resource.id) { target in
                                        Menu(model.itemTitle(target)) {
                                            ThreadItemActions(resource: target.resource, model: model)
                                        }
                                    }
                                } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton).fixedSize().frame(width: 24, height: 28)
                                .accessibilityLabel("Actions for \(group.application.name) items")
                            }
                            ForEach(group.targets, id: \.resource.id) { target in
                                ThreadItemRow(target: target, model: model).padding(.leading, 38)
                            }
                        }
                        Divider()
                    }
                    if model.groups.isEmpty && !model.loading { Text("No confirmed resume targets.").foregroundStyle(.secondary) }
                    if let selected = model.selected {
                        if !model.context.isEmpty {
                            Label("\(model.context) · observed", systemImage: "arrow.triangle.branch")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        DisclosureGroup("Other observed metadata") {
                            let shown = Set(model.groups.flatMap(\.targets).map(\.resource.id))
                            ForEach(selected.resources.filter { !shown.contains($0.resource.id) }, id: \.resource.id) { edge in
                                ThreadItemRow(target: RestoreTarget(resource: edge.resource), model: model)
                                    .help(edge.status == .provisional ? "Provisional evidence; excluded from resume" : "Supporting metadata; excluded from duplicate resume operations")
                            }
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if model.nextResource != nil {
                        Button("Load more observed items") { Task { await model.loadMore() } }.disabled(model.loading)
                    }
                }.padding(18)
            }
            Divider()
            HStack {
                if let message = model.message { Text(message).lineLimit(1).help(message) }
                else if let message = restoration?.message { Text(message).lineLimit(1).help(message) }
                Spacer()
                if let restoration, !restoration.items.isEmpty {
                    Button("Resume details") { restoration.showingOutcomes = true }
                }
                Button("⌘K Actions", action: openActions).keyboardShortcut("k")
            }.font(.system(size: 11)).foregroundStyle(.secondary).buttonStyle(.plain)
                .padding(.horizontal, 18).frame(height: 36)
        }
        .frame(width: 700, height: 550)
        .task(id: model.selectedID) { await model.refresh() }
        .onExitCommand { model.presented = false }
        .sheet(isPresented: Binding(get: { restoration?.showingOutcomes ?? false },
                                   set: { restoration?.showingOutcomes = $0 })) {
            if let restoration { ResumeOutcomesView(model: restoration) }
        }
        .popover(isPresented: $showingActions) {
            ThreadActionPanel(model: model, restoration: restoration, dismiss: { showingActions = false }, details: { showingActions = false })
        }
    }
    private func openActions() {
        if let actions { actions() } else { showingActions = true }
    }
    private var header: some View {
        HStack(spacing: 12) {
            Button { model.presented = false } label: { Image(systemName: "chevron.left").frame(width: 26, height: 32) }
                .buttonStyle(.plain).accessibilityLabel("Back to Threads")
            VStack(alignment: .leading, spacing: 3) {
                Text(model.selected?.thread.title ?? "Thread").font(.system(size: 16, weight: .semibold)).lineLimit(1)
                if !model.context.isEmpty { Text(model.context).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            if let thread = model.selected?.thread {
                Text(thread.lastActiveAt, style: .relative).font(.system(size: 11)).foregroundStyle(.secondary)
                if let restoration {
                    Button("Resume") {
                        Task { await restoration.restore(thread.id, title: thread.title, plan: model.resumePlan) }
                    }.buttonStyle(.plain).disabled(thread.isArchived || restoration.busy).keyboardShortcut(.defaultAction)
                }
            }
            Button(action: openActions) { Image(systemName: "ellipsis").frame(width: 26, height: 32) }
                .buttonStyle(.plain).accessibilityLabel("Thread actions")
        }.padding(.horizontal, 18).frame(height: 66)
    }
}
