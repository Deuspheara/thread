import Darwin
import Foundation

/// Runs read-only Git commands with bounded output, cancellation, and a hard deadline.
struct GitCommandRunner: GitCommandRunning {
    let timeout: Duration
    let outputLimit: Int

    init(timeout: Duration = .seconds(3), outputLimit: Int = 65_536) {
        self.timeout = timeout
        self.outputLimit = outputLimit
    }

    func run(directory: String, arguments: [String]) async throws -> GitCommandResult {
        try Task.checkCancellation()
        let deadline = ContinuousClock.now.advanced(by: timeout)
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null",
                             "-C", directory] + arguments
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C", "GIT_TERMINAL_PROMPT": "0",
                               "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_OPTIONAL_LOCKS": "0"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let terminated = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingNewest(1))
        process.terminationHandler = { child in
            terminated.continuation.yield(child.terminationStatus)
            terminated.continuation.finish()
        }
        do { try process.run() } catch { throw GitReadError.unavailable }
        output.fileHandleForWriting.closeFile()
        defer { output.fileHandleForReading.closeFile() }
        guard ContinuousClock.now < deadline else {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw GitReadError.timedOut
        }
        return try await withTaskCancellationHandler {
            try await collect(process: process, output: output.fileHandleForReading, terminated: terminated.stream, deadline: deadline)
        } onCancel: {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    private func collect(process: Process, output: FileHandle, terminated: AsyncStream<Int32>, deadline: ContinuousClock.Instant) async throws -> GitCommandResult {
        try await withThrowingTaskGroup(of: GitCommandResult.self) { group in
            group.addTask {
                var bytes = Data()
                for try await byte in output.bytes {
                    guard bytes.count < outputLimit else { throw GitReadError.oversizedOutput }
                    bytes.append(byte)
                }
                for await status in terminated { return GitCommandResult(status: status, output: bytes) }
                throw CancellationError()
            }
            group.addTask {
                try await Task.sleep(until: deadline, clock: .continuous)
                throw GitReadError.timedOut
            }
            defer {
                group.cancelAll()
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            guard let result = try await group.next() else { throw GitReadError.unavailable }
            return result
        }
    }
}
