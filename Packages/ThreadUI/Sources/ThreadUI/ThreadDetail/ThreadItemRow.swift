import SwiftUI
import ThreadDomain

/// Presents one useful destination with explicit per-Thread correction actions.
struct ThreadItemRow: View {
    let target: RestoreTarget
    @Bindable var model: ThreadDetailModel
    private var label: ResourceLabel { ResourceLabel() }
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: target.isProject ? "folder" : label.symbol(target.resource)).foregroundStyle(.secondary).frame(width: 16)
            Text(model.itemTitle(target)).lineLimit(1).help(label.title(target.resource))
            Spacer(minLength: 4)
            Text(target.isProject ? "Project" : ThreadResumePlan.directory(target.resource) != nil ? "Directory" : label.kind(target.resource)).font(.system(size: 10)).foregroundStyle(.secondary)
            Menu { ThreadItemActions(resource: target.resource, model: model) } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .fixedSize().frame(width: 24, height: 28)
            .accessibilityLabel("Actions for \(label.title(target.resource))")
        }
        .font(.system(size: 12)).frame(minHeight: 33)
        .accessibilityElement(children: .contain)
    }
}


/// Shares persisted item correction actions between item rows and application header menus.
struct ThreadItemActions: View {
    let resource: Resource
    @Bindable var model: ThreadDetailModel
    var body: some View {
                if resource.kind == .file {
                    Button("Use application when resuming…") {
                        Task {
                            model.choosingApplication = true
                            defer { model.choosingApplication = false }
                            if let choice = await ApplicationChoice.choose() {
                                await model.chooseApplication(choice, for: resource.id)
                            }
                        }
                    }.disabled(model.selected?.thread.isArchived == true)
                }
                Menu("Move to another Thread") {
                    ForEach(model.destinations, id: \.id) { destination in
                        Button(destination.title) { Task { await model.reassign(resource.id, to: destination.id) } }
                    }
                }.disabled(model.destinations.isEmpty)
    }
}
