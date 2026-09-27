import SwiftUI

/// Explains local observation and optional access before the first Thread session.
struct OnboardingView: View {
    let model: OnboardingModel
    let close: () -> Void
    let showSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 18)).foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                    .background(.quaternary, in: Circle())
                Text("Welcome to Thread").font(.system(size: 16, weight: .semibold))
                Spacer()
                closeButton
            }
            .padding(.horizontal, 20).frame(height: 58)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Pick up where you left off.")
                            .font(.system(size: 27, weight: .semibold))
                        Text("Thread groups related work on this Mac. Press ⌥ Space to find it again.")
                            .font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Works offline and saves activity metadata locally", systemImage: "externaldrive")
                        Label("Remote inference is off until you enable it", systemImage: "network.slash")
                        Label("Never records your screen or document contents", systemImage: "lock.shield")
                    }
                    .font(.system(size: 12))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
                    if model.permission == .granted {
                        Label("Window access enabled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        AccessibilityPermissionView(request: model.requestPermission,
                            openSettings: model.openPermissionSettings, refresh: model.refreshPermission)
                    }
                    if model.settingsUnavailable {
                        Text("Open System Settings → Privacy & Security → Accessibility.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Connect browser tabs or terminal directories later") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("These integrations are optional. Browser tabs need the Thread extension. Terminal directories need a shell hook that you choose to install.")
                            Button("Open setup guide…", action: model.openSetupGuide)
                                .threadActionButton()
                            if model.guideUnavailable { Text("The setup guide could not be opened.") }
                        }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                    }.font(.system(size: 12))
                }
                .padding(24)
            }
            Divider()
            HStack {
                Text("You can add integrations later.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Settings…", action: showSettings)
                    .threadActionButton()
                if model.rememberFailed && !model.hasStarted {
                    Button("Continue for this session") { model.beginSession(); close() }
                        .threadActionButton()
                }
                Button(model.hasStarted ? "Done" : "Start Thread") {
                    if !model.hasStarted { model.begin() }
                    if model.hasStarted { close() }
                }
                .keyboardShortcut(.defaultAction)
                .threadActionButton(prominent: true)
            }
            .threadGlassActionGroup()
            .padding(.horizontal, 20).frame(height: 58)
        }
        .frame(width: 620, height: 570)
        .threadPanelSurface()
        .onAppear { model.refreshPermission() }
        .onExitCommand(perform: close)
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 32, height: 32)
        }
        .modifier(WelcomeCloseSurface())
        .accessibilityLabel("Close welcome")
    }
}

/// Gives the welcome window's close control a circular surface.
private struct WelcomeCloseSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.plain).background(.quaternary, in: Circle())
        }
    }
}
