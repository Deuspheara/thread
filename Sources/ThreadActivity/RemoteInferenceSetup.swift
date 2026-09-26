import Foundation
import OSLog
import ThreadDomain
import ThreadDecisions
import ThreadMacOS
import ThreadPersistence

/// Applies saved remote consent, endpoint-scoped credentials and routing at the application boundary.
@MainActor
public final class RemoteInferenceSetup {
    let connection = RemoteDecisionConnection()
    private let file: RemoteInferencePreferencesFile
    private let credentials: ThreadCredentialActions
    private var preferences: RemoteInferencePreferences = .disabled
    private var readFailed = false
    private var preparation: Task<Void, Never>?

    public init(directory: URL, credentials: ThreadCredentialActions = .keychain) {
        self.credentials = credentials
        file = RemoteInferencePreferencesFile(directory: directory)
        do { preferences = try file.load() }
        catch { readFailed = true; log("Remote preferences unavailable; inference stays local") }
    }

    public func prepare() async {
        if let preparation { await preparation.value; return }
        let configured: (any DecisionEngine)?
        do { configured = try engine(for: preferences) }
        catch { configured = nil; log("Remote configuration rejected; inference stays local") }
        let connection = connection
        let task = Task { await connection.configure(configured) }
        preparation = task
        await task.value
    }

    public func state() async throws -> RemoteInferenceState {
        if readFailed { throw RemoteInferenceSetupError.preferencesUnavailable }
        var availability: SessionCredentialAvailability = .notStored
        if let endpoint = preferences.endpoint {
            do { _ = try await credentials.read(endpoint); availability = .stored }
            catch SessionCredentialError.missing { availability = .notStored }
            catch { availability = .unavailable; log("Thread credential availability cannot be checked") }
        }
        return RemoteInferenceState(preferences: preferences, credential: availability)
    }

    public func apply(_ value: RemoteInferencePreferences, token: String?) async throws {
        try await disable()
        do {
            let configured = try engine(for: value)
            if let endpoint = value.endpoint {
                if let token { try await credentials.save(endpoint, token) }
                if value.enabled { _ = try await credentials.read(endpoint) }
            } else if token != nil { throw RemoteInferencePreferenceError.invalidEndpoint }
            try file.save(value)
            preferences = value; readFailed = false
            await connection.configure(configured)
        } catch {
            if error is PreferenceFileError { readFailed = true }
            throw mapped(error)
        }
    }

    public func disable() async throws {
        await prepare()
        await connection.configure(nil)
        let shouldSave = preferences.enabled || readFailed
        preferences = try RemoteInferencePreferences(enabled: false, endpoint: preferences.endpoint)
        do { if shouldSave { try file.save(preferences) }; readFailed = false }
        catch { readFailed = true; log("Remote disable preference could not be saved"); throw RemoteInferenceSetupError.preferencesUnavailable }
    }

    public func forget() async throws {
        var preferenceFailure = false
        do { try await disable() }
        catch { preferenceFailure = true }
        do {
            if let endpoint = preferences.endpoint { try await credentials.remove(endpoint) }
        } catch {
            log("Thread credential removal unavailable; inference stays local")
            throw RemoteInferenceSetupError.credentialRemovalFailed(preferencesSaved: !preferenceFailure)
        }
        if preferenceFailure { throw RemoteInferenceSetupError.credentialRemovedPreferencesUnavailable }
    }

    private func engine(for value: RemoteInferencePreferences) throws -> (any DecisionEngine)? {
        guard value.enabled, let endpoint = value.endpoint else { return nil }
        let credentials = credentials
        return try JevDecisionEngine(endpoint: endpoint, bearerToken: { try await credentials.read(endpoint) })
    }

    private func mapped(_ error: Error) -> Error {
        log("Remote configuration change unavailable; inference stays local")
        switch error {
        case SessionCredentialError.invalidCredential: return RemoteInferenceSetupError.invalidCredential
        case SessionCredentialError.missing: return RemoteInferenceSetupError.credentialMissing
        case is SessionCredentialError: return RemoteInferenceSetupError.credentialUnavailable
        case is RemoteInferencePreferenceError: return error
        default: return RemoteInferenceSetupError.preferencesUnavailable
        }
    }

    private func log(_ message: StaticString) {
        Logger(subsystem: "app.thread.desktop", category: "classification").error("\(message)")
    }
}
