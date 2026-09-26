import Foundation
import ThreadDomain

/// Selects bounded inference metadata without copying restoration or event payloads.
struct DecisionPayloadBuilder {
    func build(context: ActivityContext, candidates: [ScoredThreadCandidate]) -> DecisionPayloadDraft {
        let resources = evidence(context)
        var seen: Set<ThreadID> = []
        var selected: [DecisionPayloadDraft.Candidate] = []
        for scored in candidates {
            guard seen.insert(scored.candidate.id).inserted else { continue }
            selected.append(DecisionPayloadDraft.Candidate(id: scored.candidate.id, relevance: scored.relevance,
                signals: scored.signals, matchingResources: resources.indices.filter {
                    scored.candidate.resourceIDs.contains(resources[$0].id)
                }, secondsSinceActive: context.endedAt.timeIntervalSince(scored.candidate.lastActiveAt)))
            if selected.count == 8 { break }
        }
        return DecisionPayloadDraft(seconds: context.endedAt.timeIntervalSince(context.startedAt),
            resources: resources, candidates: selected)
    }

    private func evidence(_ context: ActivityContext) -> [DecisionPayloadDraft.Evidence] {
        var seen: Set<ResourceID> = []
        var resources: [DecisionPayloadDraft.Evidence] = []
        for evidence in context.resources {
            guard seen.insert(evidence.resource.id).inserted else { continue }
            resources.append(DecisionPayloadDraft.Evidence(id: evidence.resource.id, kind: evidence.resource.kind,
                value: value(evidence.resource), seconds: evidence.lastSeen.timeIntervalSince(evidence.firstSeen)))
            if resources.count == 128 { break }
        }
        return resources
    }

    private func value(_ resource: Resource) -> String? {
        switch resource {
        case .application(let application): application.identity.bundleIdentifier
        case .repository(let repository): repository.rootPath
        case .branch(_, let name): name
        case .file(let file): file.path
        case .browserPage(let page): page.url
        case .window, .terminal, .workingDirectory: nil
        }
    }
}
