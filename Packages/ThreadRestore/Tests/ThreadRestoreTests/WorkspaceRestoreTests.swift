import Foundation
import Testing
import ThreadDomain
@testable import ThreadRestore

struct WorkspaceRestoreTests {
    @Test func workspaceRestorationRequiresAnExistingWorkspaceFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("team's work.code-workspace")
        try Data("{}".utf8).write(to: workspace)
        let restorer = VSCodeRestorer()
        #expect(restorer.workspaceURL(.file(FileIdentity(path: workspace.path))) == workspace)
        #expect(restorer.workspaceURL(.file(FileIdentity(path: root.appendingPathComponent("missing.code-workspace").path))) == nil)
        #expect(restorer.workspaceURL(.workingDirectory(root.path)) == nil)
        let directory = root.appendingPathComponent("directory.code-workspace")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(restorer.workspaceURL(.file(FileIdentity(path: directory.path))) == nil)
        #expect(restorer.workspaceURL(.file(FileIdentity(path: "relative.code-workspace"))) == nil)
    }
}
