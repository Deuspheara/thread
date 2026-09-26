import Foundation
import ThreadDomain

/// Reads porcelain-v2 branch headers and tracked-change counts, discarding filenames.
struct GitStatusSnapshot {
    let branch: String?
    let head: String?
    let dirty: RepositoryDirtySummary

    init(data: Data) throws {
        var branch: String?
        var head: String?
        var sawBranch = false
        var sawHead = false
        var changed = 0
        var conflicts = 0
        for bytes in data.split(separator: 0) {
            if bytes.first == 49 || bytes.first == 50 { changed += 1; continue }
            if bytes.first == 117 { changed += 1; conflicts += 1; continue }
            guard bytes.first == 35, let record = String(data: Data(bytes), encoding: .utf8) else { continue }
            if record.hasPrefix("# branch.head ") {
                let value = String(record.dropFirst(14))
                branch = value == "(detached)" ? nil : value
                sawBranch = true
            } else if record.hasPrefix("# branch.oid ") {
                let value = String(record.dropFirst(13))
                head = value == "(initial)" ? nil : value
                sawHead = true

            }
        }
        guard sawBranch, sawHead else { throw GitReadError.malformedOutput }
        self.branch = branch
        self.head = head
        dirty = RepositoryDirtySummary(changedTrackedFiles: changed, conflictedFiles: conflicts)
    }
}
