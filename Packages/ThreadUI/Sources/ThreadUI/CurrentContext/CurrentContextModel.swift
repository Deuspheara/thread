import Foundation
import Observation
import ThreadDomain

/// Owns presentation state and forwards observation/permission/startup intent to injected actions.
@MainActor
@Observable
public final class CurrentContextModel {
    public enum StorageState { case preparing, ready, unavailable }
    public private(set) var context: CurrentContext
    public private(set) var storage: StorageState = .preparing
    public private(set) var browserAvailable = true
    public private(set) var shellAvailable = true
    public private(set) var settingsUnavailable = false
    private let prepareStorage: @MainActor @Sendable () async throws -> Void
    private let refreshObservation: @MainActor @Sendable () -> Void
    private let requestAuthorization: @MainActor @Sendable () -> Void
    private let openAuthorizationSettings: @MainActor @Sendable () -> Bool
    private var preparing = false

    public init(
        context: CurrentContext = CurrentContext(),
        prepareStorage: @escaping @MainActor @Sendable () async throws -> Void,
        refreshObservation: @escaping @MainActor @Sendable () -> Void,
        requestAuthorization: @escaping @MainActor @Sendable () -> Void,
        openAuthorizationSettings: @escaping @MainActor @Sendable () -> Bool
    ) {
        self.context = context
        self.prepareStorage = prepareStorage
        self.refreshObservation = refreshObservation
        self.requestAuthorization = requestAuthorization
        self.openAuthorizationSettings = openAuthorizationSettings
    }

    public func updateHistoryStatus(_ status: HistoryStatus) {
        switch status {
        case .unavailable, .unsaved: storage = .unavailable
        case .saved: storage = .ready
        case .loading, .sessionOnly: break
        }
    }

    public func setBrowserAvailable(_ available: Bool) { browserAvailable = available }

    public func setShellAvailable(_ available: Bool) { shellAvailable = available }

    public func update(_ context: CurrentContext) { self.context = context }
    public func refresh() { refreshObservation() }
    public func requestPermission() { requestAuthorization() }

    public func openSettings() {
        settingsUnavailable = !openAuthorizationSettings()
    }

    public func prepare() async {
        guard !preparing else { return }
        preparing = true
        storage = .preparing
        defer { preparing = false }
        do {
            try await prepareStorage()
            storage = .ready
        } catch {
            storage = .unavailable
        }
    }
}
