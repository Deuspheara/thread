import Foundation
import Observation
import ThreadDomain

/// Edits explicit remote consent and forwards configuration intents without transport or Keychain access.
@MainActor @Observable
public final class RemoteInferenceModel {
    public var enabled = false
    public var endpointText = ""
    public var credentialText = ""
    public private(set) var busy = false
    public private(set) var credential: SessionCredentialAvailability = .notStored
    public private(set) var message: String?
    private let load: @MainActor () async throws -> RemoteInferenceState
    private let save: @MainActor (RemoteInferencePreferences, String?) async throws -> Void
    private let disable: @MainActor () async throws -> Void
    private let forget: @MainActor () async throws -> Void

    public init(load: @escaping @MainActor () async throws -> RemoteInferenceState,
                save: @escaping @MainActor (RemoteInferencePreferences, String?) async throws -> Void,
                disable: @escaping @MainActor () async throws -> Void, forget: @escaping @MainActor () async throws -> Void) {
        self.load = load; self.save = save; self.disable = disable; self.forget = forget
    }

    public func reload() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { display(try await load()); message = nil }
        catch is CancellationError { return }
        catch { explain(error) }
    }

    public func apply() async {
        guard !busy else { return }
        busy = true
        let token = credentialText.isEmpty ? nil : credentialText
        credentialText = ""
        defer { busy = false }
        do {
            try await disable()
            let raw = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
            let endpoint = raw.isEmpty ? nil : URL(string: raw)
            if !raw.isEmpty && endpoint == nil { throw RemoteInferencePreferenceError.invalidEndpoint }
            let value = try RemoteInferencePreferences(enabled: enabled, endpoint: endpoint)
            try await save(value, token)
            display(try await load())
            message = enabled ? "Saved. Ambiguous decisions may use your backend." : "Saved. Inference is local."
        } catch { enabled = false; explain(error) }
    }

    public func stop() async {
        guard !busy else { return }
        busy = true; enabled = false; credentialText = ""
        defer { busy = false }
        do { try await disable(); message = "Remote inference stopped. Local matching continues." }
        catch { explain(error) }
    }

    public func removeCredential() async {
        guard !busy else { return }
        busy = true; enabled = false; credentialText = ""
        defer { busy = false }
        do { try await forget(); credential = .notStored; message = "Saved credential removed. Inference is local." }
        catch { explain(error) }
    }

    private func display(_ state: RemoteInferenceState) {
        enabled = state.preferences.enabled
        endpointText = state.preferences.endpoint?.absoluteString ?? ""
        credential = state.credential
        credentialText = ""
    }

    private func explain(_ error: Error) {
        switch error {
        case IntentCompletionError.unknown: message = "Connection lost. Remote settings may have changed. Reload to check consent and credentials before retrying."
        case is RemoteInferencePreferenceError: message = "Enter a complete HTTPS endpoint without credentials, query or fragment."
        case RemoteInferenceSetupError.invalidCredential: message = "Use the independent Thread token from your backend, not an OpenRouter key."
        case RemoteInferenceSetupError.credentialMissing: message = "Save a Thread token for this exact endpoint before enabling remote inference."
        case RemoteInferenceSetupError.credentialUnavailable: message = "Thread could not access the Keychain. Restart Thread and retry; if it persists, check your login Keychain access."
        case RemoteInferenceSetupError.credentialRemovalFailed(let saved):
            message = saved ? "Credential could not be removed. Remote inference is disabled. Check your login Keychain access and retry removal."
                : "Credential could not be removed, and disabling could not be saved. Inference is local for this session; retry before restarting."
        case RemoteInferenceSetupError.credentialRemovedPreferencesUnavailable:
            credential = .notStored
            message = "Credential removed. Inference is local, but disabling could not be saved. Retry before restarting."
        default: message = "Configuration could not be saved or loaded. Retry; changes may not persist across restart."
        }
    }
}
