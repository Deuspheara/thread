import Foundation
import Testing
import ThreadPersistence

@MainActor
struct OnboardingCompletionTests {
    @Test func completionReopensAndCorruptionCannotBypassSetup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record("Onboarding fixture cleanup failed") }
        }
        let store = OnboardingCompletionFile(directory: directory)
        #expect(try !store.isComplete())
        try store.complete()
        #expect(try OnboardingCompletionFile(directory: directory).isComplete())
        let url = directory.appendingPathComponent("OnboardingComplete")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try Data("corrupt".utf8).write(to: url)
        #expect(throws: PreferenceFileError.self) { try store.isComplete() }
    }
}
