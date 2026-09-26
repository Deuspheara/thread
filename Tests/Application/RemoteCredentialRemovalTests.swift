import Foundation
import Testing
import ThreadDomain
import ThreadPersistence
import ThreadMacOS
import ThreadUI
@testable import ThreadApp
@testable import ThreadActivity

@MainActor
struct RemoteCredentialRemovalTests {
    @Test func deniedRemovalPersistsDisabledConsentBeforeKeychainFailure() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("thread-removal-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferences = try RemoteInferencePreferences(enabled: true, endpoint: URL(string: "https://fixture.example/v1/decisions")!)
        let file = RemoteInferencePreferencesFile(directory: directory)
        try file.save(preferences)
        let credentials = ThreadCredentialActions(read: { _ in String(repeating: "a", count: 43) },
            save: { _, _ in Issue.record("Unexpected credential replacement") }, remove: { _ in throw SessionCredentialError.accessDenied })
        let setup = RemoteInferenceSetup(directory: directory, credentials: credentials)
        await setup.prepare()
        #expect(await setup.connection.availableEngine() != nil)
        await #expect(throws: RemoteInferenceSetupError.credentialRemovalFailed(preferencesSaved: true)) { try await setup.forget() }
        #expect(await setup.connection.availableEngine() == nil)
        #expect(try !file.load().enabled)
        let restarted = RemoteInferenceSetup(directory: directory, credentials: credentials)
        await restarted.prepare()
        #expect(await restarted.connection.availableEngine() == nil)
    }

    @Test func failedPreferenceWriteStillAttemptsDeletionAndReportsBothOutcomes() async throws {
        for denied in [false, true] {
            let directory = URL.temporaryDirectory.appendingPathComponent("thread-removal-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let value = try RemoteInferencePreferences(enabled: true, endpoint: URL(string: "https://fixture.example/v1/decisions")!)
            try RemoteInferencePreferencesFile(directory: directory).save(value)
            let probe = RemovalProbe(denied: denied)
            let credentials = ThreadCredentialActions(read: { _ in String(repeating: "a", count: 43) },
                save: { _, _ in Issue.record("Unexpected credential replacement") }, remove: { _ in try await probe.remove() })
            let setup = RemoteInferenceSetup(directory: directory, credentials: credentials)
            await setup.prepare()
            let path = directory.appendingPathComponent("RemoteInference.json")
            try FileManager.default.removeItem(at: path)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
            let model = RemoteInferenceModel(load: { try await setup.state() }, save: { try await setup.apply($0, token: $1) },
                disable: { try await setup.disable() }, forget: { try await setup.forget() })
            await model.reload()
            await model.removeCredential()
            #expect(await probe.attempted)
            #expect(await setup.connection.availableEngine() == nil)
            #expect(!model.enabled && !model.busy)
            #expect(model.message?.contains("retry before restarting") == true || model.message?.contains("Retry before restarting") == true)
            if denied { #expect(model.credential == .stored) }
            else { #expect(model.credential == .notStored) }
        }
    }
}

private actor RemovalProbe {
    private let denied: Bool
    private(set) var attempted = false
    init(denied: Bool) { self.denied = denied }
    func remove() throws {
        attempted = true
        if denied { throw SessionCredentialError.accessDenied }
    }
}
