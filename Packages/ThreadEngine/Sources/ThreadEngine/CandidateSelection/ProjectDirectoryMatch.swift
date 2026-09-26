import Foundation
import ThreadDomain

/// Matches a document representing an exact known project directory without filesystem reads.
struct ProjectDirectoryMatch {
    func matches(_ identities: Set<ResourceID>, candidate: ThreadCandidate) -> Bool {
        let known = Set(candidate.projectDirectories.compactMap(normalize))
        guard !known.isEmpty else { return false }
        return identities.contains { identity in
            let path: String
            switch identity {
            case .file(let file): path = file.path
            case .workingDirectory(let directory): path = directory
            default: return false
            }
            return normalize(path).map(known.contains) ?? false
        }
    }

    private func normalize(_ path: String) -> String? {
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        let value = URL(fileURLWithPath: path).standardizedFileURL.path
        // Shared filesystem roots are not specific project evidence.
        return value == "/" ? nil : value
    }
}
