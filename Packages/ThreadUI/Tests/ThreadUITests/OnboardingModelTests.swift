import Testing
import Observation
import ThreadDomain
@testable import ThreadUI

@MainActor
struct OnboardingModelTests {
    @Test func startupRequiresIntentAndRememberFailureDoesNotStartObservation() {
        enum Failure: Error { case unavailable }
        var starts = 0
        var remembered = 0
        let model = make(complete: false, remember: { remembered += 1; throw Failure.unavailable }, start: { starts += 1 })
        #expect(starts == 0)
        model.begin()
        #expect(!model.hasStarted)
        #expect(model.rememberFailed)
        #expect(starts == 0)
        model.beginSession()
        model.beginSession()
        model.begin()
        #expect(model.hasStarted)
        #expect(starts == 1 && remembered == 1)
    }

    @Test func completionAndPermissionAreIndependent() {
        var starts = 0
        var remembered = 0
        let model = make(complete: false, remember: { remembered += 1 }, start: { starts += 1 })
        model.refreshPermission()
        #expect(model.permission == .notGranted)
        model.begin()
        model.begin()
        #expect(model.hasStarted)
        #expect(starts == 1 && remembered == 1)
    }

    @Test func checkAgainRefreshesOnlyAfterConsentAndTracksLatePermissionChanges() async {
        let state = CurrentContextModel(context: CurrentContext(permission: .notGranted),
            prepareStorage: {}, refreshObservation: {}, requestAuthorization: {}, openAuthorizationSettings: { false })
        var refreshes = 0
        var requests = 0
        let model = OnboardingModel(complete: false, remember: {}, start: {},
            readPermission: { state.context.permission }, refreshAccess: { refreshes += 1 },
            requestAccess: { requests += 1 }, openSettings: { false }, openGuide: { false })
        model.refreshPermission()
        #expect(refreshes == 0 && requests == 0)
        model.beginSession()
        model.refreshPermission()
        #expect(refreshes == 1 && requests == 0)
        let changes = AsyncStream<Bool>.makeStream()
        withObservationTracking { _ = model.permission } onChange: { changes.continuation.yield(true) }
        state.update(CurrentContext(permission: .granted))
        model.refreshPermission()
        changes.continuation.finish()
        var iterator = changes.stream.makeAsyncIterator()
        let change = await iterator.next()
        #expect(change != nil)
        #expect(model.permission == .granted)
    }

    private func make(complete: Bool, remember: @escaping @MainActor () throws -> Void,
                      start: @escaping @MainActor () -> Void) -> OnboardingModel {
        OnboardingModel(complete: complete, remember: remember, start: start,
                        readPermission: { .notGranted }, refreshAccess: {}, requestAccess: {}, openSettings: { false }, openGuide: { false })
    }
}
