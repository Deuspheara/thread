import SwiftUI
import ThreadDomain

/// Keeps Thread corrections in a compact keyboard-navigable action palette.
struct ThreadActionPanel: View {
    @Bindable var model: ThreadDetailModel
    let restoration: ThreadRestoreModel?
    let dismiss: () -> Void
    let details: () -> Void
    @State private var selection = 0
    @State private var editing: String?
    @State private var split: ThreadSplitModel?
    @FocusState private var navigating: Bool
    @FocusState private var enteringText: Bool
    private var titles: [String] {
        ["Resume", "Details", model.selected?.thread.isPinned == true ? "Unpin" : "Pin", "Rename…", "Merge…", "Split…",
         model.selected?.thread.isArchived == true ? "Unarchive" : "Archive"]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(editing ?? "Thread actions").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).accessibilityLabel("Close actions")
            }
            if model.loading { ProgressView().controlSize(.small) }
            if editing == "Rename" {
                TextField("Thread title", text: $model.title).focused($enteringText).onSubmit { rename() }
                    .task { await Task.yield(); enteringText = true }
                Button("Save name", action: rename).keyboardShortcut(.defaultAction)
                    .disabled(model.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else if editing == "Merge" {
                TextField("Find destination Thread", text: $model.destinationQuery).focused($enteringText)
                    .task { await Task.yield(); enteringText = true }
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.destinations, id: \.id) { target in
                            Button("Merge into \(target.title)") { Task { await model.merge(into: target.id); dismiss(); details() } }
                                .buttonStyle(.plain).padding(.vertical, 6)
                        }
                    }
                }.frame(maxHeight: 200)
                Text("Combines resources and archives this Thread. Saved history remains.").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                        Button { perform(index) } label: {
                            HStack { Text(title); Spacer(); if selection == index { Image(systemName: "return").foregroundStyle(.secondary) } }
                                .padding(.horizontal, 9).frame(height: 30)
                                .background(selection == index ? Color.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        }.buttonStyle(.plain).disabled(unavailable(index))
                            .accessibilityValue(selection == index ? "Selected action" : "")
                    }
                }
                .focusable().focused($navigating).focusEffectDisabled()
                .onKeyPress(.downArrow) { selection = min(titles.count - 1, selection + 1); return .handled }
                .onKeyPress(.upArrow) { selection = max(0, selection - 1); return .handled }
                .onKeyPress(.return) { perform(selection); return .handled }
            }
            if let message = model.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .font(.system(size: 13)).padding(12).frame(width: 290)
        .onAppear { navigating = true }
        .task(id: model.selectedID) { await model.refresh() }
        .onExitCommand { if editing != nil { editing = nil; navigating = true } else { dismiss() } }
        .sheet(item: $split) { ThreadSplitView(model: $0) }
    }
    private func unavailable(_ index: Int) -> Bool {
        guard let detail = model.selected else { return true }
        return model.busy || (index == 0 && (restoration == nil || detail.thread.isArchived || restoration?.busy == true))
            || ([4, 5].contains(index) && detail.thread.isArchived) || (index == 5 && detail.resources.count < 2)
    }
    private func rename() {
        Task { await model.rename(); if model.message == "Updated." { dismiss() } }
    }
    private func perform(_ index: Int) {
        guard !unavailable(index), let thread = model.selected?.thread else { return }
        switch index {
        case 0:
            dismiss()
            Task { await restoration?.restore(thread.id, title: thread.title, plan: model.resumePlan) }
        case 1: dismiss(); details()
        case 2: Task { await model.togglePin() }
        case 3: editing = "Rename"
        case 4: editing = "Merge"
        case 5: split = model.makeSplit()
        case 6: Task { await model.toggleArchive() }
        default: break
        }
    }
}
