import Foundation
import Testing
import ThreadDomain
import ThreadPersistence
import ThreadMacOS
import ThreadUI
@testable import ThreadApp
@testable import ThreadActivity

@MainActor
struct RemoteInferenceSetupTests {
    @Test func consentCredentialsAndEndpointSwitchRemainIndependent() async throws {
        let directory = temporary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = FakeThreadCredentials()
        let setup = RemoteInferenceSetup(directory: directory, credentials: vault.actions)
        await setup.prepare()
        #expect(await setup.connection.availableEngine() == nil)
        let one = try RemoteInferencePreferences(enabled: true, endpoint: URL(string: "https://one.example/v1/decisions")!)
        try await setup.apply(one, token: String(repeating: "a", count: 43))
        #expect(await setup.connection.availableEngine() != nil)
        #expect(try RemoteInferencePreferencesFile(directory: directory).load() == one)
        let two = try RemoteInferencePreferences(enabled: true, endpoint: URL(string: "https://two.example/v1/decisions")!)
        await #expect(throws: RemoteInferenceSetupError.credentialMissing) { try await setup.apply(two, token: nil) }
        #expect(await setup.connection.availableEngine() == nil)
        #expect(await vault.endpoints == [one.endpoint!])
        try await setup.disable()
        #expect(try !RemoteInferencePreferencesFile(directory: directory).load().enabled)
    }

    @Test func corruptPreferenceDocumentsNeverRestoreRemoteConsent() async throws {
        let directory = temporary()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let document = directory.appendingPathComponent("RemoteInference.json")
        for data in [Data("broken".utf8), Data(#"{"enabled":true,"endpoint":"http://unsafe.example/"}"#.utf8), Data(repeating: 32, count: 16_385)] {
            try data.write(to: document)
            let setup = RemoteInferenceSetup(directory: directory, credentials: FakeThreadCredentials().actions)
            await setup.prepare()
            #expect(await setup.connection.availableEngine() == nil)
            await #expect(throws: RemoteInferenceSetupError.preferencesUnavailable) { try await setup.state() }
        }
    }

    @Test func removingCredentialDisablesRoutingAndPersistsLocalMode() async throws {
        let directory = temporary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = FakeThreadCredentials()
        let setup = RemoteInferenceSetup(directory: directory, credentials: vault.actions)
        let value = try RemoteInferencePreferences(enabled: true, endpoint: URL(string: "https://one.example/v1/decisions")!)
        try await setup.apply(value, token: String(repeating: "a", count: 43))
        try await setup.forget()
        #expect(await vault.endpoints.isEmpty)
        #expect(await setup.connection.availableEngine() == nil)
        #expect(try await setup.state().credential == .notStored)
        let file = RemoteInferencePreferencesFile(directory: directory)
        #expect(try !file.load().enabled)
        let raw = try String(contentsOf: directory.appendingPathComponent("RemoteInference.json"), encoding: .utf8)
        #expect(!raw.contains(String(repeating: "a", count: 43)))
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("RemoteInference.json").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func modelClearsEnteredSecretsAndStopsBeforeRejectingInvalidConfiguration() async throws {
        let directory = temporary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let setup = RemoteInferenceSetup(directory: directory, credentials: FakeThreadCredentials().actions)
        let model = RemoteInferenceModel(load: { try await setup.state() }, save: { try await setup.apply($0, token: $1) },
            disable: { try await setup.disable() }, forget: { try await setup.forget() })
        model.enabled = true
        model.endpointText = "https://one.example/v1/decisions"
        model.credentialText = String(repeating: "a", count: 43)
        await model.apply()
        #expect(model.enabled && model.credential == .stored && model.credentialText.isEmpty)
        model.endpointText = "http://unsafe.example/"
        model.credentialText = "sk-or-do-not-store-provider-key"
        await model.apply()
        #expect(!model.enabled && model.credentialText.isEmpty)
        #expect(await setup.connection.availableEngine() == nil)
        #expect(try !RemoteInferencePreferencesFile(directory: directory).load().enabled)
    }

    @Test func startupCannotReenableRoutingAfterStopAndWriteFailuresRemainLocal() async throws {
        let directory = temporary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let value = try RemoteInferencePreferences(enabled: true, endpoint: URL(string: "https://one.example/v1/decisions")!)
        let file = RemoteInferencePreferencesFile(directory: directory)
        try file.save(value)
        let setup = RemoteInferenceSetup(directory: directory, credentials: FakeThreadCredentials().actions)
        async let startup: Void = setup.prepare()
        try await setup.disable()
        await startup
        #expect(await setup.connection.availableEngine() == nil)
        try await setup.apply(value, token: String(repeating: "a", count: 43))
        let path = directory.appendingPathComponent("RemoteInference.json")
        try FileManager.default.removeItem(at: path)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        await #expect(throws: RemoteInferenceSetupError.preferencesUnavailable) { try await setup.disable() }
        #expect(await setup.connection.availableEngine() == nil)
        await #expect(throws: RemoteInferenceSetupError.preferencesUnavailable) { try await setup.state() }
    }

    private func temporary() -> URL { URL.temporaryDirectory.appendingPathComponent("thread-remote-" + UUID().uuidString) }
}

private actor FakeThreadCredentials {
    private var tokens: [URL: String] = [:]
    var endpoints: Set<URL> { Set(tokens.keys) }
    nonisolated var actions: ThreadCredentialActions {
        ThreadCredentialActions(read: { try await self.read($0) }, save: { await self.save($0, $1) }, remove: { await self.remove($0) })
    }
    func read(_ endpoint: URL) throws -> String {
        guard let token = tokens[endpoint] else { throw SessionCredentialError.missing }
        return token
    }
    func save(_ endpoint: URL, _ token: String) { tokens[endpoint] = token }
    func remove(_ endpoint: URL) { tokens.removeValue(forKey: endpoint) }
}
