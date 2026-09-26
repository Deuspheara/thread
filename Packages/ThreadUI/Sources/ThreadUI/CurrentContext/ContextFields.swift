import SwiftUI
import ThreadDomain

/// Formats a small metadata snapshot for the observation panel.
struct ContextFields: View {
    let context: CurrentContext

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            row("Application", value: context.application?.name ?? "Waiting for an application")
            row("Window", value: windowLabel)
            if let frame = context.window?.frame {
                row("Frame", value: "\(frame.width.formatted(.number.precision(.fractionLength(0)))) × \(frame.height.formatted(.number.precision(.fractionLength(0)))) at \(frame.x.formatted(.number.precision(.fractionLength(0)))), \(frame.y.formatted(.number.precision(.fractionLength(0))))")
            }
            if let tab = context.browserTab {
                row("Browser", value: tab.domain)
                row("Tab", value: tab.title.isEmpty ? tab.url : tab.title)
            }
            if let terminal = context.terminal {
                row("Last terminal", value: terminal.workingDirectory)
                if let status = context.terminalExitStatus { row("Exit status", value: String(status)) }
            }
            if let repository = context.repository {
                switch repository {
                case .available(let value):
                    row("Repository", value: value.rootPath)
                    row("Branch", value: value.branch ?? "Detached HEAD")
                    row(value.dirty.isApproximate ? "Tracked changes ≈" : "Tracked changes", value: String(value.dirty.changedTrackedFiles))
                case .notRepository: row("Git", value: "Outside a repository")
                case .unavailable: row("Git", value: "Metadata temporarily unavailable")
                }
            }
            if let updated = context.updatedAt {
                GridRow {
                    Text("Updated").foregroundStyle(.secondary)
                    Text(updated, style: .relative).monospacedDigit()
                }
            }
        }
        .font(.callout)
    }

    private func row(_ label: String, value: String) -> some View {
        GridRow(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Text(value).lineLimit(3).textSelection(.enabled)
        }
    }

    private var windowLabel: String {
        switch context.windowAvailability {
        case .available: context.window?.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Title unavailable"
        case .permissionRequired: "Accessibility access needed"
        case .waiting: "Waiting for window metadata"
        case .noFocusedWindow: "No focused window"
        case .unsupported: "This application does not expose its window"
        case .temporarilyUnavailable: "Window temporarily unavailable"
        }
    }
}
