import Foundation
import ThreadDomain

/// Persists only public remote configuration and explicit consent outside the activity database.
@MainActor
public struct RemoteInferencePreferencesFile {
    private let url: URL
    public init(directory: URL) { url = directory.appendingPathComponent("RemoteInference.json") }

    public func load() throws -> RemoteInferencePreferences {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 16_384 else { throw PreferenceFileError.unavailable }
            let decoded = try JSONDecoder().decode(RemoteInferencePreferences.self, from: Data(contentsOf: url))
            return try RemoteInferencePreferences(enabled: decoded.enabled, endpoint: decoded.endpoint)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return .disabled }
        catch { throw PreferenceFileError.unavailable }
    }

    public func save(_ preferences: RemoteInferencePreferences) throws {
        do {
            let validated = try RemoteInferencePreferences(enabled: preferences.enabled, endpoint: preferences.endpoint)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(validated).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw PreferenceFileError.unavailable }
    }
}
