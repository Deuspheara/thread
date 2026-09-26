import Foundation

/// Neutralizes repository-configured content filters before inspecting worktree status.
struct GitFilterPolicy {
    static func overrides(from result: GitCommandResult) throws -> [String] {
        guard result.status == 0 || result.status == 1 else { throw GitReadError.unavailable }
        guard let text = String(data: result.output, encoding: .utf8) else { throw GitReadError.malformedOutput }
        var arguments: [String] = []
        for key in text.split(separator: "\0") {
            guard key.hasPrefix("filter."), [".clean", ".smudge", ".process", ".required"].contains(where: key.hasSuffix) else {
                throw GitReadError.malformedOutput
            }
            arguments += ["-c", String(key) + (key.hasSuffix(".required") ? "=false" : "=")]
        }
        return arguments
    }
}
