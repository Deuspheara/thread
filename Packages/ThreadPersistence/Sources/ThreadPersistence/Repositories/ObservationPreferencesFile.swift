import Foundation
import ThreadDomain

/// Atomically stores the small privacy preference document independently of activity history.
@MainActor
public struct ObservationPreferencesFile {
    private let url: URL
    public init(directory: URL) { url = directory.appendingPathComponent("ObservationPreferences.json") }

    public func load() throws -> ObservationExclusions {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 65_536 else { throw PreferenceFileError.unavailable }
            let decoded = try JSONDecoder().decode(ObservationExclusions.self, from: Data(contentsOf: url))
            return try ObservationExclusions(applications: decoded.applications, domains: decoded.domains)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return ObservationExclusions()
        } catch { throw PreferenceFileError.unavailable }
    }

    public func save(_ exclusions: ObservationExclusions) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(exclusions)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw PreferenceFileError.unavailable }
    }
}

public enum PreferenceFileError: Error, Sendable { case unavailable }
