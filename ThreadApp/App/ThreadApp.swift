import AppKit
import SwiftUI
import ThreadUI

@main
struct ThreadApp: App {
    @NSApplicationDelegateAdaptor(ThreadAppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Thread", systemImage: "square.stack.3d.up") {
            @Bindable var detail = delegate.runtime.detail
            VStack(spacing: 0) {
                Button("Open switcher · ⌥ Space") { delegate.showSwitcher() }.padding(12)
                if delegate.runtime.switcher.shortcutUnavailable {
                    Text("⌥ Space is unavailable. Open the switcher here.").font(.caption).padding(.horizontal)
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ThreadSearchView(model: delegate.runtime.search, open: delegate.runtime.detail.open)
                        RecentThreadsView(model: delegate.runtime.threads, open: delegate.runtime.detail.open)
                        DisclosureGroup("Observed context") {
                            CurrentContextView(model: delegate.runtime.model)
                        }.padding(.horizontal, 12)
                    }
                }.frame(maxHeight: 600)
                Divider()
                Button("Getting started…") { delegate.showOnboarding() }.padding(.top, 8)
                SettingsLink().padding(.top, 8)
                Button("Check for Updates…") { delegate.updates.check() }
                    .disabled(!delegate.updates.canCheck).padding(.top, 8)
                if let message = delegate.updates.message {
                    Text(message).font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                }
                Button("Quit Thread") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                    .padding(12)
            }
            .sheet(isPresented: $detail.presented, onDismiss: { Task { await delegate.runtime.search.refresh() } }) { ThreadDetailView(model: detail) }
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView(login: delegate.loginLaunch, exclusions: delegate.runtime.exclusions, remote: delegate.runtime.remoteInference)
        }
    }
}
