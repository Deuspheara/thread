import Foundation
import Testing
import ThreadDomain
import ThreadAgentTransport
@testable import ThreadApp

struct AgentClientRecoveryTests {
    @Test func storageRetryStartsObservationAfterFailedInitialLaunch() async throws {
        let transport = FixtureAgentRequests(failFirstStart: true)
        let client = AgentClient(connection: transport, debugDirectory: nil)
        await #expect(throws: AgentTransportError.self) { try await client.start() }
        try await client.prepare()
        #expect(await transport.startCount == 2)
        #expect(await transport.prepareCount >= 1)
    }

    @Test func readingSettingsDoesNotAuthorizeObservation() async throws {
        let transport = FixtureAgentRequests(failFirstStart: false)
        let client = AgentClient(connection: transport, debugDirectory: nil)
        _ = try await client.remoteState()
        #expect(await transport.startCount == 0)
    }

    @Test func quittingBeforeSetupMakesNoRequestsAndClosesOnce() async {
        let transport = FixtureAgentRequests(failFirstStart: false)
        let client = AgentClient(connection: transport, debugDirectory: nil)
        await client.shutdown()
        await client.shutdown()
        #expect(await transport.requestCount == 0)
        #expect(await transport.closeCount == 1)
    }

    @Test func lateConfigurationCannotStartObservationAfterQuit() async {
        let transport = FixtureAgentRequests(failFirstStart: false, pauseConfiguration: true)
        let client = AgentClient(connection: transport, debugDirectory: nil)
        let startup = Task { try await client.start() }
        await transport.waitForConfiguration()
        await client.shutdown()
        await transport.releaseConfiguration()
        await #expect(throws: CancellationError.self) { try await startup.value }
        #expect(await transport.startCount == 0)
        #expect(await transport.requestCount == 1)
    }

    @Test func helperReportedUncertainCompletionRemainsUnknownToTheCaller() async throws {
        let transport = FixtureAgentRequests(failFirstStart: false, reportsUncertainCompletion: true)
        let client = AgentClient(connection: transport, debugDirectory: nil)
        _ = try await client.start()
        await #expect(throws: IntentCompletionError.self) {
            try await client.edit(.pin(ThreadID(rawValue: UUID()), pinned: true))
        }
        #expect(await transport.editCount == 1)
    }

    @Test func lostEditAcknowledgementIsUnknownAndNeverReplayedByARead() async throws {
        let transport = FixtureAgentRequests(failFirstStart: false)
        let client = AgentClient(connection: transport, debugDirectory: nil)
        _ = try await client.start()
        await #expect(throws: IntentCompletionError.self) {
            try await client.edit(.pin(ThreadID(rawValue: UUID()), pinned: true))
        }
        _ = try await client.recentSummaries(limit: 20)
        #expect(await transport.editCount == 1)
    }
}

/// Simulates acknowledgements at the process boundary without creating observers or storage.
private actor FixtureAgentRequests: AgentRequesting {
    private var failFirstStart: Bool
    private let reportsUncertainCompletion: Bool
    private let pauseConfiguration: Bool
    private let configurationEntered = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private var configurationReply: CheckedContinuation<AgentReplyBody, Never>?
    private(set) var requestCount = 0
    private(set) var closeCount = 0
    private(set) var startCount = 0
    private(set) var prepareCount = 0
    private(set) var editCount = 0

    init(failFirstStart: Bool, pauseConfiguration: Bool = false, reportsUncertainCompletion: Bool = false) {
        self.failFirstStart = failFirstStart
        self.pauseConfiguration = pauseConfiguration
        self.reportsUncertainCompletion = reportsUncertainCompletion
    }

    func waitForConfiguration() async {
        for await _ in configurationEntered.stream { return }
    }

    func releaseConfiguration() {
        configurationReply?.resume(returning: .done)
        configurationReply = nil
    }
    nonisolated func contexts() -> AsyncStream<CurrentContext> { AsyncStream { $0.finish() } }
    nonisolated func updates() -> AsyncStream<ThreadPresentation> { AsyncStream { $0.finish() } }
    func shutdownIfConnected() {}
    func close() { closeCount += 1 }

    func request(_ command: AgentCommand) async throws -> AgentReplyBody {
        requestCount += 1
        switch command {
        case .configure:
            if !pauseConfiguration { return .done }
            return await withCheckedContinuation { continuation in
                configurationReply = continuation
                configurationEntered.continuation.yield(())
            }
        case .shutdown: return .done
        case .start:
            startCount += 1
            if failFirstStart { failFirstStart = false; throw AgentTransportError.unavailable }
            return .availability(AgentAvailability(shell: true, browser: true, processIdentifier: 123))
        case .prepare: prepareCount += 1; return .done
        case .edit:
            editCount += 1
            if reportsUncertainCompletion { return .failure(.completionUnknown) }
            throw AgentTransportError.unavailable
        case .recent: return .summaries([])
        case .remoteState: return .remote(RemoteInferenceState(preferences: .disabled, credential: .notStored))
        default: throw AgentTransportError.invalidMessage
        }
    }
}
