import Foundation

/// Remembers explicit completion without opening the activity database or sharing global preferences.
@MainActor
public struct OnboardingCompletionFile {
    private let url: URL
    public init(directory: URL) { url = directory.appendingPathComponent("OnboardingComplete") }

    public func isComplete() throws -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.size] as? NSNumber)?.intValue == 1,
                  try Data(contentsOf: url) == Data([49]) else { throw PreferenceFileError.unavailable }
            return true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return false
        } catch { throw PreferenceFileError.unavailable }
    }

    public func complete() throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try Data([49]).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw PreferenceFileError.unavailable }
    }
}
