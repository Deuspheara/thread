import Foundation

/// Holds bounded, validated application identifiers and exact-or-subdomain exclusions.
public struct ObservationExclusions: Codable, Equatable, Sendable {
    public let applications: [String]
    public let domains: [String]

    public init() { applications = []; domains = [] }

    public init(applications: [String], domains: [String]) throws {
        guard applications.count <= 64, domains.count <= 64 else { throw ExclusionError.tooManyEntries }
        self.applications = try Self.normalize(applications, domain: false)
        self.domains = try Self.normalize(domains, domain: true)
    }

    public func excludes(application: String) -> Bool { applications.contains(application.lowercased()) }

    public func excludes(url: String) -> Bool {
        guard let host = URLComponents(string: url)?.host?.lowercased() else { return true }
        let canonical = host.hasSuffix(".") ? String(host.dropLast()) : host
        return domains.contains { canonical == $0 || canonical.hasSuffix("." + $0) }
    }

    private static func normalize(_ entries: [String], domain: Bool) throws -> [String] {
        var result: Set<String> = []
        for entry in entries {
            let value = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !value.isEmpty, value.utf8.count <= 253,
                  value.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 })
            else { throw ExclusionError.invalidEntry }
            let labels = value.split(separator: ".", omittingEmptySubsequences: false)
            guard labels.allSatisfy({ !$0.isEmpty && (!domain || ($0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-"))) })
            else { throw ExclusionError.invalidEntry }
            result.insert(value)
        }
        return result.sorted()
    }
}

public enum ExclusionError: Error, Sendable {
    case invalidEntry
    case tooManyEntries
}
