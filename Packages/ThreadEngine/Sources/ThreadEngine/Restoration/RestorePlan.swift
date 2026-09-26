import Foundation
import ThreadDomain

/// Orders confirmed resources and avoids reopening a directory represented by several graph edges.
struct RestorePlan {
    let directoryIdentity: @Sendable (String) -> String

    init(directoryIdentity: @escaping @Sendable (String) -> String = {
        URL(fileURLWithPath: $0).standardizedFileURL.path
    }) { self.directoryIdentity = directoryIdentity }

    func resources(_ detail: ThreadDetail) -> [Resource] {
        let confirmed = detail.resources.filter { $0.status == .confirmed }.map(\.resource)
        let ordered = confirmed.filter { $0.kind == .application } + confirmed.filter { $0.kind == .terminal }
            + confirmed.filter { $0.kind != .application && $0.kind != .terminal && $0.kind != .window }
            + confirmed.filter { $0.kind == .window }
        var directories = Set<String>()
        return ordered.filter { resource in
            guard let path = directory(resource) else { return true }
            return directories.insert(directoryIdentity(path)).inserted
        }
    }

    private func directory(_ resource: Resource) -> String? {
        switch resource {
        case .terminal(let terminal): terminal.workingDirectory
        case .workingDirectory(let path): path
        case .repository(let repository): repository.rootPath
        default: nil
        }
    }
}
