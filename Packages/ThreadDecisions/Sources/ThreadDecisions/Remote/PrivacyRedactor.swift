import Foundation
import ThreadDomain

/// Converts local draft values into bounded, allowlisted remote inference metadata.
struct PrivacyRedactor {
    func redact(_ draft: DecisionPayloadDraft) -> PreparedDecisionPayload {
        let resources = draft.resources.prefix(128).enumerated().map { index, evidence in
            RedactedDecisionPayload.Evidence(alias: "r\(index)", kind: evidence.kind,
                label: label(evidence.value, kind: evidence.kind), observedSeconds: seconds(evidence.seconds))
        }
        let candidates = draft.candidates.prefix(8).enumerated().map { index, candidate in
            RedactedDecisionPayload.Candidate(alias: "c\(index)", relevance: probability(candidate.relevance),
                signals: Array(Set(candidate.signals)).sorted { $0.rawValue < $1.rawValue },
                matchingResources: Array(Set(candidate.matchingResources.filter { resources.indices.contains($0) }))
                    .sorted().map { resources[$0].alias }, secondsSinceActive: seconds(candidate.secondsSinceActive))
        }
        let mapping = Dictionary(uniqueKeysWithValues: draft.candidates.prefix(8).enumerated().map { ("c\($0.offset)", $0.element.id) })
        return PreparedDecisionPayload(payload: RedactedDecisionPayload(schemaVersion: 1,
            observedSeconds: seconds(draft.seconds), resources: resources, candidates: candidates), candidateIDs: mapping)
    }

    private func label(_ raw: String?, kind: ResourceKind) -> String? {
        guard let raw, raw.utf8.count <= 8192 else { return nil }
        switch kind {
        case .repository, .file:
            guard raw.hasPrefix("/"), !raw.contains("\0") else { return nil }
            return identifier(URL(fileURLWithPath: raw).lastPathComponent)
        case .application: return identifier(raw)
        case .branch:
            guard !raw.hasPrefix("/"), !raw.hasSuffix("/"), !raw.contains("..") else { return nil }
            return identifier(raw, allowSlash: true)
        case .browserPage: return domain(raw)
        case .window, .terminal, .workingDirectory: return nil
        }
    }

    private func identifier(_ value: String, allowSlash: Bool = false) -> String? {
        guard !value.isEmpty, value.utf8.count <= 128 else { return nil }
        let allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-+" + (allowSlash ? "/" : "")
        guard value.unicodeScalars.allSatisfy({ allowed.unicodeScalars.contains($0) }) else { return nil }
        return value
    }

    private func domain(_ raw: String) -> String? {
        guard let url = URLComponents(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, let host = url.host?.lowercased(),
              host.contains("."), let safe = identifier(host),
              safe.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty }) else { return nil }
        return safe
    }

    private func seconds(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(max(value, 0), 30 * 24 * 60 * 60))
    }

    private func probability(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}
