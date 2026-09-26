import Foundation
import Observation
import ThreadDomain

/// Presents cancellable local history searches without exposing storage details.
@MainActor @Observable
public final class ThreadSearchModel {
    public var query = ""
    public var includeArchived = false
    public private(set) var results: [ThreadSearchResult] = []
    public private(set) var isLoading = false
    public private(set) var failed = false
    @ObservationIgnored private let search: any ThreadSearch
    @ObservationIgnored private var revision = 0

    public init(search: any ThreadSearch) { self.search = search }

    public func refresh() async {
        revision += 1
        let request = revision
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = []
        failed = false
        isLoading = !text.isEmpty
        guard !text.isEmpty else { return }
        do {
            try await Task.sleep(for: .milliseconds(150))
            let found = try await search.search(query: text, includeArchived: includeArchived, limit: 30)
            guard request == revision, !Task.isCancelled else { return }
            results = found
            isLoading = false
        } catch {
            guard request == revision else { return }
            isLoading = false
            failed = !Task.isCancelled
        }
    }
}
