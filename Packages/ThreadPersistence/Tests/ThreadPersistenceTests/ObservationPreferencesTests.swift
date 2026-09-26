import Foundation
import Testing
import ThreadDomain
import ThreadPersistence

@MainActor
struct ObservationPreferencesTests {
    @Test func preferencesReopenAndCorruptOrOversizedFilesFailClosed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ObservationPreferencesFile(directory: directory)
        #expect(try store.load() == ObservationExclusions())
        let rules = try ObservationExclusions(applications: ["com.apple.Mail"], domains: ["example.com"])
        try store.save(rules)
        #expect(try ObservationPreferencesFile(directory: directory).load() == rules)
        let url = directory.appendingPathComponent("ObservationPreferences.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try Data("invalid".utf8).write(to: url)
        #expect(throws: PreferenceFileError.self) { try store.load() }
        try Data(repeating: 32, count: 65_537).write(to: url)
        #expect(throws: PreferenceFileError.self) { try store.load() }
    }
}
