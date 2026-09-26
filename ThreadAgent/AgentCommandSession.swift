import Foundation
import Darwin
import OSLog
import ThreadDomain
import ThreadActivity
import ThreadAgentTransport

/// Owns one configured activity runtime and translates bounded application intents into domain ports.
@MainActor
final class AgentCommandSession {
    private let appBundle: Bundle
    private var activity: ActivitySession?
    private var directory: URL?
    private var availability: AgentAvailability?
    private var owner: AgentPeerLifetime?
    private var publisher: AgentPublicationChannel?
    private var publicationTasks: [Task<Void, Never>] = []
    private let requestQueue = AgentRequestQueue()
    private var shutdownTask: Task<Void, Never>?

    init(appBundle: Bundle) { self.appBundle = appBundle }

    func submit(_ request: AgentRequest, peer: AgentPeerLifetime, publisher: AgentPublicationChannel, reply: @escaping @Sendable (Data?) -> Void) {
        guard peer.isActive else {
            reply(try? AgentCommandCodec.encode(AgentReply(id: request.id, body: .failure(.cancelled))))
            return
        }
        guard owner == nil || owner === peer else {
            reply(try? AgentCommandCodec.encode(AgentReply(id: request.id, body: .failure(.busy))))
            return
        }
        owner = peer
        self.publisher = publisher
        if case .shutdown = request.command { requestQueue.cancelAll(except: request.id) }
        requestQueue.submit(request.id, operation: { [weak self] in
            guard let self, peer.isActive, owner === peer else { return .failure(.cancelled) }
            return await execute(request.command)
        }, reply: reply)
    }

    func cancel(_ id: UUID, peer: AgentPeerLifetime) {
        guard peer.isActive, owner == nil || owner === peer else { return }
        owner = peer
        requestQueue.cancel(id)
    }

    func disconnected(_ peer: AgentPeerLifetime) async {
        peer.retire()
        guard owner === peer else { return }
        requestQueue.cancelAll()
        await shutdown()
        guard owner === peer else { return }
        owner = nil
        publisher = nil
        requestQueue.clearCancellationHistory()
    }


    func execute(_ command: AgentCommand) async -> AgentReplyBody {
        var began = false
        do {
            try Task.checkCancellation()
            if case let .configure(path) = command { return try configure(path) }
            guard let activity, shutdownTask == nil else { return .failure(.unavailable) }
            began = true
            return try await execute(command, activity: activity)
        } catch is CancellationError {
            return .failure(began && command.requiresCompletionAcknowledgement ? .completionUnknown : .cancelled)
        } catch let error as ThreadEditError { return .failure(.edit(error)) }
        catch let error as ThreadReadError { return .failure(.read(error)) }
        catch let error as ThreadRestoreError { return .failure(.restore(error)) }
        catch let error as RemoteInferenceSetupError { return .failure(.remote(error)) }
        catch is RemoteInferencePreferenceError { return .failure(.invalidRequest) }
        catch is ExclusionError { return .failure(.invalidRequest) }
        catch is AgentTransportError { return .failure(.invalidRequest) }
        catch { return .failure(.unavailable) }
    }

    func shutdown() async {
        if let shutdownTask { await shutdownTask.value; return }
        guard let activity else { return }
        for task in publicationTasks { task.cancel() }
        publicationTasks.removeAll()
        let task = Task { await activity.runtime.shutdown() }
        shutdownTask = task
        await task.value
        self.activity = nil
        availability = nil
        directory = nil
        shutdownTask = nil
    }

    private func configure(_ path: String?) throws -> AgentReplyBody {
        guard shutdownTask == nil else { return .failure(.busy) }
        let resolved = try AgentStorageLocation.resolve(debugPath: path)
        if let directory {
            return directory == resolved ? .done : .failure(.invalidRequest)
        }
        directory = resolved
        activity = ActivityComposition.make(directory: resolved, appBundle: appBundle)
        return .done
    }

    private func execute(_ command: AgentCommand, activity: ActivitySession) async throws -> AgentReplyBody {
        switch command {
        case .configure: throw AgentTransportError.invalidMessage
        case .start:
            if let availability { return .availability(availability) }
            guard let started = activity.runtime.start() else { return .failure(.unavailable) }
            let value = AgentAvailability(shell: started.shell, browser: started.browser, processIdentifier: getpid())
            availability = value
            publish(activity)
            return .availability(value)
        case .prepare: try await activity.runtime.prepare(); return .done
        case .refreshObservation: activity.refreshObservation(); return .done
        case .requestPermission: activity.requestPermission(); return .done
        case .shutdown: await shutdown(); return .done
        case let .recent(limit):
            try bounded(limit, maximum: 20)
            return .summaries(try await activity.runtime.reading.recentSummaries(limit: limit))
        case let .detail(thread, cursor, limit):
            try bounded(limit, maximum: 64)
            return .detail(try await activity.runtime.reading.detailPage(thread, after: cursor, limit: limit))
        case let .destinations(query, thread, limit):
            try bounded(limit, maximum: 20); try validate(query: query)
            return .destinations(try await activity.runtime.reading.destinations(query: query, excluding: thread, limit: limit))
        case let .search(query, archived, limit):
            try bounded(limit, maximum: 100); try validate(query: query)
            return .search(try await activity.search.search(query: query, includeArchived: archived, limit: limit))
        case let .edit(edit):
            try validate(edit: edit)
            return .history(try await activity.runtime.editing.edit(edit))
        case let .restore(thread): return .restore(try await activity.restoration.restore(thread))
        case .exclusions: return .exclusions(try activity.exclusions())
        case let .saveExclusions(value):
            let checked = try ObservationExclusions(applications: value.applications, domains: value.domains)
            try await activity.saveExclusions(checked); return .done
        case .remoteState: return .remote(try await activity.remote.state())
        case let .remoteApply(value, token):
            let checked = try RemoteInferencePreferences(enabled: value.enabled, endpoint: value.endpoint)
            if let token {
                guard (32...128).contains(token.utf8.count), !token.hasPrefix("sk-or-"),
                      token.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) ||
                          (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
                    return .failure(.remote(.invalidCredential))
                }
            }
            try await activity.remote.apply(checked, token: token); return .done
        case .remoteDisable: try await activity.remote.disable(); return .done
        case .remoteForget: try await activity.remote.forget(); return .done
        }
    }

    private func publish(_ activity: ActivitySession) {
        guard let publisher, let peer = owner else { return }
        publicationTasks = [
            Task { [weak self] in
                do {
                    for await value in activity.runtime.contexts() {
                        try await publisher.send(.context(value))
                    }
                } catch { await self?.publicationFailed(error, peer: peer) }
            },
            Task { [weak self] in
                do {
                    for await value in activity.runtime.updates() {
                        try await publisher.send(.threads(value))
                    }
                } catch { await self?.publicationFailed(error, peer: peer) }
            }
        ]
    }

    private func publicationFailed(_ error: Error, peer: AgentPeerLifetime) async {
        guard owner === peer, !(error is CancellationError) else { return }
        Logger(subsystem: "app.thread.desktop", category: "agent").error("Activity publication unavailable")
        await disconnected(peer)
    }

    private func bounded(_ value: Int, maximum: Int) throws {
        guard (1...maximum).contains(value) else { throw AgentTransportError.invalidMessage }
    }

    private func validate(query: String) throws {
        guard query.utf8.count <= 256 else { throw AgentTransportError.invalidMessage }
    }

    private func validate(edit: ThreadEdit) throws {
        switch edit {
        case let .rename(_, title), let .split(_, _, title, _):
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  title.utf8.count <= 512 else { throw AgentTransportError.invalidMessage }
        default: break
        }
        if case let .split(_, _, _, resources) = edit {
            guard !resources.isEmpty, resources.count <= 512 else { throw AgentTransportError.invalidMessage }
        }
    }
}
