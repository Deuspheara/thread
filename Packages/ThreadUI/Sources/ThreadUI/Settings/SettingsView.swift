import SwiftUI

/// Presents Thread preferences in a dark sidebar window.
public struct SettingsView: View {
    /// Names the available preference pages and their sidebar icons.
    private enum Page: String, CaseIterable {
        case general = "General"
        case privacy = "Privacy"
        case inference = "Inference"

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .privacy: "hand.raised"
            case .inference: "sparkles"
            }
        }

        var summary: String {
            switch self {
            case .general: "Startup and app behavior"
            case .privacy: "Observation exclusions"
            case .inference: "Optional remote decisions"
            }
        }
    }

    private let exclusions: ObservationExclusionsModel
    private let login: LoginLaunchModel
    private let remote: RemoteInferenceModel
    private let close: () -> Void
    @State private var page: Page = .general
    @State private var search = ""
    @Environment(\.scenePhase) private var scenePhase

    public init(login: LoginLaunchModel, exclusions: ObservationExclusionsModel,
                remote: RemoteInferenceModel, close: @escaping () -> Void) {
        self.login = login
        self.exclusions = exclusions
        self.remote = remote
        self.close = close
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 228)
                .background(Color(red: 0.13, green: 0.13, blue: 0.14))
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.075, green: 0.075, blue: 0.08))
        }
        .frame(width: 800, height: 610)
        .preferredColorScheme(.dark)
        .threadPanelSurface()
        .onAppear { login.refresh() }
        .onExitCommand(perform: close)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { login.refresh() }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: close) {
                Circle()
                    .fill(Color(red: 1, green: 0.36, blue: 0.34))
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(.black.opacity(0.2)))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close settings")
            .padding(.top, 12)
            .padding(.bottom, 26)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search settings", text: $search)
                    .textFieldStyle(.plain)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(.white.opacity(0.12), in: Capsule())
            .padding(.bottom, 20)

            HStack(spacing: 10) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 17))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.09), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thread").font(.system(size: 12, weight: .semibold))
                    Text("Settings").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 7)
            .padding(.bottom, 20)

            Text("PREFERENCES")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            ForEach(matchingPages, id: \.self) { item in
                Button { page = item } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 20)
                            .foregroundStyle(page == item ? .white : .secondary)
                        Text(item.rawValue)
                            .font(.system(size: 12, weight: page == item ? .semibold : .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                    .background(page == item ? Color.white.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == item ? .isSelected : [])
            }
            Spacer()
            Text("Your activity history stays on this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 12)
    }

    private var matchingPages: [Page] {
        guard !search.isEmpty else { return Page.allCases }
        return Page.allCases.filter {
            $0.rawValue.localizedCaseInsensitiveContains(search)
                || $0.summary.localizedCaseInsensitiveContains(search)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(page.rawValue).font(.system(size: 20, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 28)
            .frame(height: 72)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch page {
                    case .general: generalContent
                    case .privacy: ObservationExclusionsView(model: exclusions)
                    case .inference: RemoteInferenceView(model: remote)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Startup")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 0) {
                Toggle("Open at Login", isOn: Binding(
                    get: { login.isRequested }, set: { login.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .tint(Color(red: 0.65, green: 0.34, blue: 0.68))
                .disabled(login.status == .unavailable)
                .font(.system(size: 12, weight: .medium))
                .padding(14)
                Divider().padding(.horizontal, 14)
                Text("Keep Thread available to observe and continue your work.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(14)
                if login.status == .requiresApproval {
                    statusRow("Allow Thread in macOS Login Items to finish enabling launch at login.")
                }
                if login.status == .unavailable {
                    statusRow("Launch at login is unavailable for this app installation.")
                }
                if login.changeFailed {
                    statusRow("The change could not be saved. Check macOS Login Items and try again.")
                }
                if login.status == .requiresApproval || login.changeFailed {
                    Button("Open Login Items…") { login.openSystemSettings() }
                        .threadActionButton()
                        .padding([.horizontal, .bottom], 14)
                }
            }
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func statusRow(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
    }
}
