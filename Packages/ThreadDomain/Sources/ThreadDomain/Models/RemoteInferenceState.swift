import Foundation

/// Describes configuration failures without exposing transport or credential-store implementation types.
public enum RemoteInferenceSetupError: Error, Codable, Sendable, Equatable {
    case invalidCredential, credentialMissing, credentialUnavailable, preferencesUnavailable
    case credentialRemovalFailed(preferencesSaved: Bool)
    case credentialRemovedPreferencesUnavailable
}

public enum SessionCredentialAvailability: Codable, Sendable, Equatable {
    case stored, notStored, unavailable
}

/// Presents saved remote consent and credential availability without containing a secret.
public struct RemoteInferenceState: Codable, Sendable {
    public let preferences: RemoteInferencePreferences
    public let credential: SessionCredentialAvailability

    public init(preferences: RemoteInferencePreferences, credential: SessionCredentialAvailability) {
        self.preferences = preferences
        self.credential = credential
    }
}
