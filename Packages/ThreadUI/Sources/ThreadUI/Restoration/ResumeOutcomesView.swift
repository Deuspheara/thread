import SwiftUI

/// Shows item-level integration results without claiming full application state restoration.
struct ResumeOutcomesView: View {
    @Bindable var model: ThreadRestoreModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Resume details").font(.headline)
                Spacer()
                Button("Done") { model.showingOutcomes = false }.keyboardShortcut(.cancelAction)
            }
            if let message = model.message { Text(message).font(.system(size: 12)).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.application.isEmpty ? item.title : "\(item.application) · \(item.title)").lineLimit(2)
                                Spacer()
                                Text(item.status).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(item.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                }
            }
        }.padding(20).frame(width: 580, height: 380)
    }
}
