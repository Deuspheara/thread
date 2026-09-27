import SwiftUI
import ThreadDomain

/// Describes the selected Thread's actual planned operations in a single compact strip.
struct ResumePreview: View {
    let model: SwitcherModel
    var body: some View {
        HStack(spacing: 10) {
            if model.previewLoading {
                ProgressView().controlSize(.small).frame(width: 18)
                Text("Loading resume preview…").lineLimit(1)
            }
            else if model.previewUnavailable { Text("Preview unavailable · open Details to retry").lineLimit(1) }
            else if let groups = model.preview?.groups, !groups.isEmpty {
                ForEach(Array(groups.prefix(2))) { group in
                    HStack(spacing: 5) {
                        ApplicationIcon(application: group.application, size: 18)
                        Text(group.preview).lineLimit(1).truncationMode(.tail)
                    }
                    .frame(width: 190, alignment: .leading)
                    .help("\(group.application.name): \(group.description) · \(group.preview)")
                    .accessibilityLabel("\(group.application.name), \(group.preview), \(group.description)")
                }
                if groups.count > 2 { Text("+\(groups.count - 2) apps").foregroundStyle(.secondary) }
            } else { Text(model.selection == nil ? "Select a Thread to resume" : "No confirmed resume targets") }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12)).foregroundStyle(.secondary)
        .padding(.horizontal, 18).frame(height: 50)
        .transaction { $0.animation = nil }
    }
}
