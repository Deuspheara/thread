import SwiftUI

/// Shows the concrete resources and title for an explicit Thread split.
struct ThreadSplitView: View {
    @Bindable var model: ThreadSplitModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Split Thread").font(.headline)
            TextField("New Thread title", text: $model.title)
                .disabled(model.busy || model.complete)
            Text("Choose some resources to separate from “\(model.source.thread.title)”. Leave at least one in the original.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.source.resources, id: \.resource.id) { edge in
                        Toggle(ResourceLabel().title(edge.resource), isOn: Binding(
                            get: { model.selection.contains(edge.resource.id) },
                            set: { model.select(edge.resource.id, included: $0) }
                        )).toggleStyle(.checkbox)
                    }
                }
            }.disabled(model.busy || model.complete)
            Text("Selected resources will be assigned only to the new Thread. Saved history stays with the original.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = model.message { Text(message).font(.caption) }
            HStack {
                Button(model.complete ? "Done" : "Cancel") { dismiss() }.disabled(model.busy)
                Spacer()
                Button("Split Thread") { Task { await model.save() } }
                    .disabled(model.busy || !model.canSplit)
            }
        }.padding(20).frame(width: 480, height: 480)
        .interactiveDismissDisabled(model.busy)
    }
}
