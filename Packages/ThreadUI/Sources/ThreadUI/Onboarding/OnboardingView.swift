import SwiftUI

/// Explains metadata collection and optional integrations before the first observation session.
struct OnboardingView: View {
    let model: OnboardingModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Thread").font(.largeTitle.weight(.semibold))
            Text("Continue your work with ⌥ Space.").font(.title3)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Thread connects related applications, windows, browser tabs and terminal directories into activities. You can correct the groups and restore their useful resources.")
                    Text("Thread works offline and stores activity metadata on this Mac. Remote inference is off by default. If you enable it in Settings, minimized metadata goes to your Thread backend and OpenRouter. Thread does not read document contents or terminal output, collect command text by default, or record your screen.")
                        .font(.callout).foregroundStyle(.secondary)
                    if model.permission == .granted {
                        Label("Window access is allowed", systemImage: "checkmark.shield")
                    } else {
                        AccessibilityPermissionView(request: model.requestPermission,
                            openSettings: model.openPermissionSettings, refresh: model.refreshPermission)
                    }
                    if model.settingsUnavailable { Text("Open System Settings → Privacy & Security → Accessibility.").font(.caption) }
                    Text("Optional terminal setup").font(.headline)
                    Text("For zsh, run these lines in a terminal. Nothing edits your shell configuration automatically.").font(.caption)
                    Text(model.shellSetup).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text("Browser tabs require the separate Thread extension. Private tabs are ignored. Safari requires a signed shared-container build.").font(.caption)
                    Button("Browser and terminal setup guide…", action: model.openSetupGuide)
                    if model.guideUnavailable { Text("The setup guide could not be opened.").font(.caption) }
                    Text("Use Settings for privacy exclusions and opt-in launch at login. Restoration never replays commands; some resources can only be restored partially.").font(.caption)
                }
            }
            if model.rememberFailed && !model.hasStarted {
                Text("Setup could not be remembered. Try again or continue for this session.").font(.caption)
                Button("Continue for this session") { model.beginSession(); close() }
            }
            HStack {
                Spacer()
                Button(model.hasStarted ? "Done" : "Start Thread") {
                    if !model.hasStarted { model.begin() }
                    if model.hasStarted { close() }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 540, height: 620)
        .onAppear { model.refreshPermission() }
    }
}
