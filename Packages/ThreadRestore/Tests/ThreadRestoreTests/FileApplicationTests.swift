import Foundation
import Testing
import ThreadDomain
@testable import ThreadRestore

@MainActor struct FileApplicationTests {
    @Test func explicitZedUsesItsAppURLEvenForAVSCodeWorkspace() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".code-workspace")
        try Data("{}".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let zed = URL(fileURLWithPath: "/Applications/Zed.app")
        let recorder = OpenRecorder()
        let restorer = FileRestorer(applicationURL: { $0 == "dev.zed.Zed" ? zed : nil }, openDocument: { url, app in
            recorder.urls.append(url); recorder.apps.append(app); return true
        })
        let target = RestoreTarget(resource: .file(FileIdentity(path: file.path)),
            application: RestoreApplication(identity: ApplicationIdentity(bundleIdentifier: "dev.zed.Zed"), name: "Zed", origin: .explicit))
        #expect(await restorer.capability(for: target) == .resource)
        let result = try await restorer.restore(target)
        #expect(result.outcome == .restored)
        #expect(result.application == target.application)
        #expect(recorder.urls == [file])
        #expect(recorder.apps == [zed])
    }
    @Test func missingPreferredApplicationDoesNotOpenWithDefault() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let recorder = OpenRecorder()
        let restorer = FileRestorer(applicationURL: { _ in nil }, openDocument: { _, _ in recorder.calls += 1; return true })
        let target = RestoreTarget(resource: .file(FileIdentity(path: file.path)),
            application: RestoreApplication(identity: ApplicationIdentity(bundleIdentifier: "missing.editor"), name: "Missing editor", origin: .explicit))
        #expect(await restorer.capability(for: target) == .unavailable)
        let result = try await restorer.restore(target)
        #expect(result.outcome == .unavailable)
        #expect(recorder.calls == 0)
        #expect(result.explanation != nil)
        _ = try await restorer.restore(target.resource)
        #expect(recorder.calls == 1)
    }
}

@MainActor private final class OpenRecorder {
    var urls: [URL] = []
    var apps: [URL?] = []
    var calls = 0
}
