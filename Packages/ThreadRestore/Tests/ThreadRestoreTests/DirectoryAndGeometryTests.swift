import Foundation
import Testing
import ThreadDomain
@testable import ThreadRestore

struct DirectoryAndGeometryTests {
    @Test func directoryURLsPreserveLiteralShellCharactersAndRejectNonDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("name ' $(touch marker); spaces")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let restorer = TerminalRestorer()
        let result = try #require(restorer.directoryURL(.workingDirectory(directory.path)))
        #expect(result.isFileURL)
        #expect(result.path == directory.path)
        #expect(restorer.directoryURL(.workingDirectory("relative")) == nil)
        #expect(restorer.directoryURL(.workingDirectory(root.appendingPathComponent("missing").path)) == nil)
        let file = root.appendingPathComponent("file")
        try Data().write(to: file)
        #expect(restorer.directoryURL(.workingDirectory(file.path)) == nil)
    }

    @Test func directoryIdentityResolvesAliasesButKeepsDifferentDirectoriesDistinct() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("project ' $(literal)")
        let other = root.appendingPathComponent("other/project ' $(literal)")
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
        let identity = DirectoryRestoreIdentity()
        #expect(identity.canonicalPath(alias.path) == identity.canonicalPath(original.path))
        #expect(identity.canonicalPath(other.path) != identity.canonicalPath(original.path))
        let fixtureName = "thread-restore-" + UUID().uuidString
        let temporary = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(fixtureName)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        #expect(identity.canonicalPath("/tmp/" + fixtureName) == identity.canonicalPath(temporary.path))
    }

    @Test func disconnectedDisplayAndOversizedFramesStayVisible() throws {
        let screen = WindowFrame(x: 0, y: 24, width: 1440, height: 876)
        let geometry = WindowGeometry()
        let adjusted = try #require(geometry.frame(WindowFrame(x: -2000, y: -1000, width: 2000, height: 1200), screens: [screen]))
        #expect(adjusted == screen)
        let second = WindowFrame(x: -1440, y: 24, width: 1440, height: 876)
        let saved = WindowFrame(x: -1200, y: 100, width: 600, height: 400)
        #expect(geometry.frame(saved, screens: [screen, second]) == saved)
        #expect(geometry.frame(WindowFrame(x: .nan, y: 0, width: 10, height: 10), screens: [screen]) == nil)
        #expect(geometry.frame(saved, screens: []) == nil)
    }
}
