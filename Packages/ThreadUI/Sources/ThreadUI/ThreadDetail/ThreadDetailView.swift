import SwiftUI
import ThreadDomain

/// Exposes rename, archive and explicit resource correction without inference logic.
public struct ThreadDetailView: View {
    @State private var split: ThreadSplitModel?
    @State private var mergeDestination: ThreadDomain.Thread?
    @Bindable private var model: ThreadDetailModel
    public init(model: ThreadDetailModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Thread details").font(.headline)
                Spacer()
                Button("Done") { model.presented = false }.keyboardShortcut(.cancelAction)
            }
            if model.loading { ProgressView().controlSize(.small) }
            if let detail = model.selected {
                HStack {
                    TextField("Title", text: $model.title)
                    Button("Rename") { Task { await model.rename() } }
                        .disabled(model.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.title.count > 160)
                }
                Button(detail.thread.isPinned ? "Unpin Thread" : "Pin Thread") {
                    Task { await model.togglePin() }
                }
                Button(detail.thread.isArchived ? "Unarchive Thread" : "Archive Thread") {
                    Task { await model.toggleArchive() }
                }
                TextField("Search destination Threads", text: $model.destinationQuery)
                Menu("Merge into…") {
                    ForEach(model.destinations, id: \.id) { target in
                        Button(target.title) { mergeDestination = target }
                    }
                }.disabled(detail.thread.isArchived || model.destinations.isEmpty)
                Button("Split resources…") { split = model.makeSplit() }
                    .disabled(detail.thread.isArchived || detail.resources.count < 2)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(detail.resources, id: \.resource.id) { edge in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(ResourceLabel().title(edge.resource)).lineLimit(2)
                                    Text("\(ResourceLabel().kind(edge.resource)) · \(edge.userCorrected ? "Assigned by you" : edge.status == .provisional ? "Provisional" : "Inferred")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu("Move to") {
                                    ForEach(model.destinations, id: \.id) { target in
                                        Button(target.title) { Task { await model.reassign(edge.resource.id, to: target.id) } }
                                    }
                                }.disabled(model.destinations.isEmpty)
                                    .accessibilityLabel("Move \(ResourceLabel().kind(edge.resource)) to another Thread")
                            }
                        }
                    }
                }.frame(maxHeight: 300)
                Text("\(detail.resources.count) of \(model.totalResourceCount) resources").font(.caption)
                if model.nextResource != nil {
                    Button("Load more resources") { Task { await model.loadMore() } }
                        .disabled(model.loading)
                }
            }
            if let message = model.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .task(id: model.selectedID) { await model.refresh() }
        .disabled(model.busy)
        .padding(20).frame(width: 480)
        .sheet(item: $split) { ThreadSplitView(model: $0) }
        .alert("Merge Threads?", isPresented: Binding(get: { mergeDestination != nil },
               set: { if !$0 { mergeDestination = nil } }), presenting: mergeDestination) { target in
            Button("Merge") { Task { await model.merge(into: target.id) } }
            Button("Cancel", role: .cancel) { mergeDestination = nil }
        } message: { target in
            Text("Combine these resources into “\(target.title)” and archive this Thread. Previously saved history remains.")
        }
    }
}
