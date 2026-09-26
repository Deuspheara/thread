import Foundation
import Testing
import ThreadDomain
@testable import ThreadEngine

struct TicketCandidateTests {
    let now = Date(timeIntervalSince1970: 1_000)
    let repo = RepositoryIdentity(commonDirectory: "/project/.git")

    @Test func branchMatchesTicketPageWithoutAutomaticallyAssigning() throws {
        let branch = Resource.branch(repo, "fix/hc-418-reconnect")
        let known = candidate([.browserPage(.chrome, "https://tickets.example/browse/HC-418")])
        let result = try #require(ThreadCandidateSelector().select(context: context(branch), from: [known]).first)
        #expect(result.signals.contains(.sameTicket))
        #expect(result.relevance >= 0.72 && result.relevance < 0.92)
    }

    @Test func ticketCannotOverrideRepositoryOrBranchConflict() throws {
        let branch = Resource.branch(repo, "fix/HC-418")
        for known in [candidate([.branch(repo, "other/HC-418")]),
                      candidate([.branch(RepositoryIdentity(commonDirectory: "/other/.git"), "fix/HC-418")])] {
            let result = try #require(ThreadCandidateSelector().select(context: context(branch), from: [known]).first)
            #expect(result.signals.contains(.sameTicket))
            #expect(result.relevance < 0.72)
        }
    }

    @Test func queriesFragmentsHostsAndUnqualifiedNumbersAreNotTicketEvidence() {
        let current: Set<ResourceID> = [.branch(repo, "fix/HC-418")]
        let matcher = TicketIdentifierMatch()
        for raw in ["https://tickets.example/?ticket=HC-418", "https://tickets.example/#HC-418",
                    "https://HC-418.example/", "https://tickets.example/browse/HC-4180",
                    "https://tickets.example/browse/HC-0418", "https://tickets.example/issues/418",
                    "https://user:password@tickets.example/HC-418", "file:///HC-418"] {
            #expect(!matcher.matches(current, known: [.browserPage(.chrome, raw)]))
        }
        #expect(!matcher.matches([.file(FileIdentity(path: "/HC-418.swift"))], known: current))
        #expect(!matcher.matches(current, known: [.branch(repo, String(repeating: "x", count: 2_049) + "/HC-418")]))
    }

    private func candidate(_ ids: Set<ResourceID>) -> ThreadCandidate {
        ThreadCandidate(id: ThreadID(rawValue: UUID()), title: "Work", lastActiveAt: now, resourceIDs: ids)
    }

    private func context(_ resource: Resource) -> ActivityContext {
        ActivityContext(startedAt: now, endedAt: now, resources: [
            ResourceEvidence(resource: resource, firstSeen: now, lastSeen: now, source: ActivitySourceID(rawValue: "test"))
        ])
    }
}
