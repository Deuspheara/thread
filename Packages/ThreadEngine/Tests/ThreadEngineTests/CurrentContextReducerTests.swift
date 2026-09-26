import Foundation
import Testing
import ThreadDomain
import ThreadEngine

struct CurrentContextReducerTests {
    private let first = ApplicationContext(identity: ApplicationIdentity(bundleIdentifier: "app.first"), name: "First", processIdentifier: 1)
    private let second = ApplicationContext(identity: ApplicationIdentity(bundleIdentifier: "app.second"), name: "Second", processIdentifier: 2)

    @Test func switchingApplicationImmediatelyClearsOldWindow() {
        var reducer = readyReducer()
        reducer.apply(event(.windowFocused(window(for: first)), at: 2))
        reducer.apply(event(.applicationActivated(second), at: 3))
        #expect(reducer.context.application == second)
        #expect(reducer.context.window == nil)
        #expect(reducer.context.windowAvailability == .waiting)
    }

    @Test func delayedNotificationsCannotReplaceNewerFocus() {
        var reducer = readyReducer()
        reducer.apply(event(.applicationActivated(second), at: 4))
        reducer.apply(event(.windowFocused(window(for: second)), at: 5))
        reducer.apply(event(.windowFocused(window(for: first)), at: 3))
        reducer.apply(event(.applicationActivated(first), at: 2))
        reducer.apply(event(.windowUnavailable(first, .noFocusedWindow), at: 3))
        #expect(reducer.context.application == second)
        #expect(reducer.context.window?.application == second)
    }

    @Test func focusedWindowMayArriveBeforeWorkspaceActivation() {
        var reducer = readyReducer()
        reducer.apply(event(.windowFocused(window(for: second)), at: 5))
        reducer.apply(event(.applicationActivated(second), at: 4))
        #expect(reducer.context.application == second)
        #expect(reducer.context.window?.application == second)
    }

    @Test func backgroundUpdatesAndTerminationCannotStealFocus() {
        var reducer = readyReducer()
        reducer.apply(event(.windowUpdated(window(for: second)), at: 3))
        reducer.apply(event(.applicationTerminated(second), at: 4))
        reducer.apply(event(.applicationLaunched(second), at: 5))
        #expect(reducer.context.application == first)
        #expect(reducer.context.window == nil)
    }

    @Test func revocationClearsWindowAndRejectsQueuedReads() {
        var reducer = readyReducer()
        reducer.apply(event(.windowFocused(window(for: first)), at: 2))
        reducer.apply(event(.accessibilityPermissionChanged(.notGranted), at: 4))
        reducer.apply(event(.windowUpdated(window(for: first)), at: 3))
        reducer.apply(event(.windowUnavailable(first, .noFocusedWindow), at: 3))
        reducer.apply(event(.accessibilityPermissionChanged(.granted), at: 1))
        #expect(reducer.context.permission == .notGranted)
        #expect(reducer.context.window == nil)
        #expect(reducer.context.windowAvailability == .permissionRequired)
    }

    @Test func reusedProcessIDDoesNotMatchPreviousApplicationInstance() {
        var reducer = readyReducer()
        let restarted = ApplicationContext(identity: first.identity, name: first.name, processIdentifier: 1, launchDate: Date(timeIntervalSince1970: 8))
        reducer.apply(event(.applicationActivated(restarted), at: 9))
        reducer.apply(event(.applicationTerminated(first), at: 10))
        #expect(reducer.context.application == restarted)
    }

    @Test func outdatedWindowCloseCannotClearNewerWindow() {
        var reducer = readyReducer()
        let previous = window(for: first)
        let current = window(for: first)
        reducer.apply(event(.windowFocused(previous), at: 2))
        reducer.apply(event(.windowFocused(current), at: 3))
        reducer.apply(event(.windowClosed(previous.identity, first), at: 4))
        #expect(reducer.context.window == current)
    }

    @Test func permissionRecoveryRequiresFreshWindowEvidence() {
        var reducer = readyReducer()
        reducer.apply(event(.accessibilityPermissionChanged(.notGranted), at: 4))
        reducer.apply(event(.accessibilityPermissionChanged(.granted), at: 6))
        reducer.apply(event(.windowFocused(window(for: first)), at: 5))
        #expect(reducer.context.window == nil)
        reducer.apply(event(.windowFocused(window(for: first)), at: 7))
        #expect(reducer.context.windowAvailability == .available)
    }

    private func readyReducer() -> CurrentContextReducer {
        var reducer = CurrentContextReducer()
        reducer.apply(event(.accessibilityPermissionChanged(.granted), at: 0))
        reducer.apply(event(.applicationActivated(first), at: 1))
        return reducer
    }

    private func window(for application: ApplicationContext) -> WindowContext {
        WindowContext(identity: WindowIdentity(rawValue: UUID()), application: application, title: "Example", frame: nil)
    }

    private func event(_ kind: ActivityEventKind, at seconds: TimeInterval) -> ActivityEvent {
        ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: Date(timeIntervalSince1970: seconds), source: ActivitySourceID(rawValue: "test"), kind: kind)
    }
}
