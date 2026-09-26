import Foundation

struct GitCommandResult: Sendable {
    let status: Int32
    let output: Data
}

/// Isolates external process execution from repository parsing and caching.
protocol GitCommandRunning: Sendable {
    func run(directory: String, arguments: [String]) async throws -> GitCommandResult
}

enum GitReadError: Error { case unavailable, timedOut, oversizedOutput, malformedOutput }
