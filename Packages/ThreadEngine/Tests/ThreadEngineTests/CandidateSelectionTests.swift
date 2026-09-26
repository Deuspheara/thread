import Foundation
import Testing
import ThreadDomain
@testable import ThreadEngine

struct CandidateSelectionTests {
    let now = Date(timeIntervalSince1970: 1_000)
    let repo = RepositoryIdentity(commonDirectory: "/project/.git")

    func candidate(_ ids: Set<ResourceID>, age: Double = 100, id: UUID = UUID()) -> ThreadCandidate {
        ThreadCandidate(id: ThreadID(rawValue: id), title: "Example", lastActiveAt: now.addingTimeInterval(-age), resourceIDs: ids)
    }
    func context(_ resources: [Resource]) -> ActivityContext {
        ActivityContext(startedAt: now.addingTimeInterval(-2), endedAt: now, resources: resources.map {
            ResourceEvidence(resource: $0, firstSeen: now, lastSeen: now, source: ActivitySourceID(rawValue: "test"))
        })
    }

    @Test func exactBranchOutranksRecentConflictingBranchAndSharedDirectory() throws {
        let main = candidate([.branch(repo, "main"), .workingDirectory("/project")], age: 0)
        let fix = candidate([.branch(repo, "fix")], age: 1000)
        let result = ThreadCandidateSelector().select(context: context([.branch(repo, "fix"), .workingDirectory("/project")]), from: [main, fix])
        #expect(result.first?.candidate.id == fix.id)
        let conflict = try #require(result.first { $0.candidate.id == main.id })
        #expect(conflict.signals.contains(.conflictingBranch))
        #expect(conflict.relevance < 0.72)
    }

    @Test func genericApplicationAndRecencyAloneProduceNoCandidate() {
        let app = ApplicationContext(identity: ApplicationIdentity(bundleIdentifier: "example.editor"), name: "Editor", processIdentifier: 1)
        let result = ThreadCandidateSelector().select(context: context([.application(app)]), from: [candidate([.application(app.identity)], age: 0)])
        #expect(result.isEmpty)
    }

    @Test func identicalBrowserResourceCannotOverrideDifferentRepository() throws {
        let tab = BrowserTabContext(identity: BrowserTabIdentity(connection: BrowserConnectionIdentity(rawValue: UUID()), tab: 1),
                                    browser: .chrome, window: 1, url: "https://example.com/docs", domain: "example.com", title: "Docs", isActive: true)
        let wrong = candidate([.repository(RepositoryIdentity(commonDirectory: "/other/.git")), Resource.browserPage(tab).id])
        let result = try #require(ThreadCandidateSelector().select(context: context([.branch(repo, "fix"), .browserPage(tab)]), from: [wrong]).first)
        #expect(result.signals.contains(.conflictingRepository))
        #expect(result.relevance < 0.72)
    }

    @Test func projectDirectoryMatchingIsExactAndCannotOverrideBranchConflict() throws {
        let known = ThreadCandidate(id: ThreadID(rawValue: UUID()), title: "Known", lastActiveAt: now,
            resourceIDs: [.branch(repo, "main")], projectDirectories: ["/project"])
        let selector = ThreadCandidateSelector()
        let exact = try #require(selector.select(context: context([.file(FileIdentity(path: "/project/"))]), from: [known]).first)
        #expect(exact.signals.contains(.sameDirectory))
        #expect(exact.relevance >= 0.92)
        #expect(selector.select(context: context([.file(FileIdentity(path: "/project-other"))]), from: [known]).isEmpty)
        #expect(selector.select(context: context([.file(FileIdentity(path: "/project/file.swift"))]), from: [known]).isEmpty)
        let conflict = try #require(selector.select(context: context([.file(FileIdentity(path: "/project")),
            .branch(repo, "fix")]), from: [known]).first)
        #expect(conflict.signals.contains(.conflictingBranch))
        #expect(conflict.relevance < 0.72)
    }

    @Test func selectionIsBoundedAndTieOrderDoesNotDependOnInputOrder() {
        let candidates = (1...12).map { number in
            candidate([.workingDirectory("/project")], id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!)
        }
        let selector = ThreadCandidateSelector()
        let observation = context([.workingDirectory("/project")])
        let forward = selector.select(context: observation, from: candidates)
        let reverse = selector.select(context: observation, from: candidates.reversed())
        #expect(forward == reverse)
        #expect(forward.count == 8)
        #expect(forward.first?.candidate.id == candidates.first?.id)
    }
}
