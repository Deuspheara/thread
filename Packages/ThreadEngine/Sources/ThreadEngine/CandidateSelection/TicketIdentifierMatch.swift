import Foundation
import ThreadDomain

/// Finds explicit project-prefixed ticket IDs in existing branch names and public URL paths.
struct TicketIdentifierMatch {
    func matches(_ current: Set<ResourceID>, known: Set<ResourceID>) -> Bool {
        let observed = identifiers(in: current)
        return !observed.isEmpty && !observed.isDisjoint(with: identifiers(in: known))
    }

    private func identifiers(in resources: Set<ResourceID>) -> Set<String> {
        var result: Set<String> = []
        for resource in resources {
            let text: String
            switch resource {
            case .branch(_, let name): text = name
            case .browserPage(_, let raw):
                guard let url = URLComponents(string: raw),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      url.host != nil, url.user == nil, url.password == nil else { continue }
                text = url.path
            default: continue
            }
            guard text.utf8.count <= 2_048 else { continue }
            let tokens = text.uppercased().split { !$0.isASCII || !($0.isLetter || $0.isNumber || $0 == "-") }
            for token in tokens {
                let parts = token.split(separator: "-", omittingEmptySubsequences: false)
                guard parts.count >= 2 else { continue }
                for index in 0..<(parts.count - 1) {
                    let prefix = parts[index], number = parts[index + 1]
                    guard (2...10).contains(prefix.count), prefix.allSatisfy({ $0.isASCII && $0.isLetter }),
                          (1...8).contains(number.count), number.allSatisfy({ $0.isASCII && $0.isNumber }),
                          number.first != "0" else { continue }
                    result.insert("\(prefix)-\(number)")
                }
            }
        }
        return result
    }
}
