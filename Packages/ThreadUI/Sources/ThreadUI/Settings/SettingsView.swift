import SwiftUI

/// Displays opt-in startup behavior and the system's approval state.
public struct SettingsView: View {
    private let exclusions: ObservationExclusionsModel
    private let login: LoginLaunchModel
    private let remote: RemoteInferenceModel
    @Environment(\.scenePhase) private var scenePhase

    public init(login: LoginLaunchModel, exclusions: ObservationExclusionsModel, remote: RemoteInferenceModel) {
        self.login = login
        self.exclusions = exclusions
        self.remote = remote
    }

    public var body: some View {
        Form {
            RemoteInferenceView(model: remote)
            ObservationExclusionsView(model: exclusions)
            Section("Startup") {
                Toggle("Launch Thread at login", isOn: Binding(
                    get: { login.isRequested }, set: { login.setEnabled($0) }
                ))
                .disabled(login.status == .unavailable)
                Text("Keep Thread available to observe and continue your work.")
                    .font(.caption).foregroundStyle(.secondary)
                if login.status == .requiresApproval {
                    Text("Allow Thread in macOS Login Items to finish enabling launch at login.")
                        .font(.caption)
                    Button("Open Login Items…") { login.openSystemSettings() }
                }
                if login.status == .unavailable {
                    Text("Launch at login is unavailable for this app installation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if login.changeFailed {
                    Text("The change could not be saved. Check macOS Login Items and try again.")
                        .font(.caption).foregroundStyle(.red)
                    Button("Open Login Items…") { login.openSystemSettings() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 720)
        .onAppear { login.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { login.refresh() }
        }
    }
}
