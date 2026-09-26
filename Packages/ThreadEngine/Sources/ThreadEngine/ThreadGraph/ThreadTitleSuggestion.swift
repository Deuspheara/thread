import Foundation
import ThreadDomain

/// Derives a bounded initial title from explicit metadata, without provider-generated names.
struct ThreadTitleSuggestion {
    func title(for context: ActivityContext) -> String {
        for evidence in context.resources.reversed() {
            if case .repository(let repository) = evidence.resource {
                let name = URL(fileURLWithPath: repository.rootPath).lastPathComponent
                return bounded(repository.branch.map { "\(name) · \($0)" } ?? name)
            }
        }
        for evidence in context.resources.reversed() {
            switch evidence.resource {
            case .file(let file): return bounded(URL(fileURLWithPath: file.path).lastPathComponent)
            case .browserPage(let page): return bounded(page.title.isEmpty ? page.domain : page.title)
            case .workingDirectory(let path): return bounded(URL(fileURLWithPath: path).lastPathComponent)
            default: continue
            }
        }
        return "Untitled work"
    }
    private func bounded(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled work" : String(trimmed.prefix(160))
    }
}
