import AppKit
import SwiftUI
import ThreadUI

@main
struct ThreadApp: App {
    @NSApplicationDelegateAdaptor(ThreadAppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Thread", systemImage: "square.stack.3d.up") {
            Button("Open Switcher") { delegate.showSwitcher() }
                .keyboardShortcut(" ", modifiers: .option)
            if delegate.runtime.switcher.shortcutUnavailable {
                Text("Option–Space is unavailable; open the switcher here")
            }
            Divider()
            Button("Getting Started…") { delegate.showOnboarding() }
            Button("Settings…") { delegate.showSettings() }
                .keyboardShortcut(",")
            Button("Check for Updates…") { delegate.updates.check() }
                .disabled(!delegate.updates.canCheck)
            Divider()
            Button("Quit Thread") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
