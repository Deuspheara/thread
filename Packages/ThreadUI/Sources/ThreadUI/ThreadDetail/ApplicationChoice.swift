import AppKit
import ThreadDomain

/// Lets the user select a local application for subsequent resumes of one Thread item.
@MainActor
enum ApplicationChoice {
    static func choose() async -> RestoreApplication? {
        let picker = NSOpenPanel()
        picker.title = "Use application when resuming this item in this Thread"
        picker.prompt = "Use Application"
        picker.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        picker.allowedContentTypes = [.applicationBundle]
        let response = await withCheckedContinuation { continuation in
            picker.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let url = picker.url, let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier else { return nil }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        let choice = RestoreApplication(identity: ApplicationIdentity(bundleIdentifier: identifier), name: name, origin: .explicit)
        return choice.isValid ? choice : nil
    }
}
