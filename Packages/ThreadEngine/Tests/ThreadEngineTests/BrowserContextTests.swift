import Foundation
import Testing
import ThreadDomain
import ThreadEngine

struct BrowserContextTests {
    @Test func unrelatedTabCloseAndConnectionLossDoNotClearCurrentTab() {
        var reducer = CurrentContextReducer()
        let first = tab(connection: UUID())
        let second = tab(connection: UUID())
        reducer.apply(event(.browserTabActivated(first)))
        reducer.apply(event(.browserTabClosed(second.identity)))
        reducer.apply(event(.browserDisconnected(second.identity.connection)))
        #expect(reducer.context.browserTab == first)
        reducer.apply(event(.browserFocusCleared(first.identity.connection)))
        #expect(reducer.context.browserTab == nil)
    }
    @Test func openingBackgroundTabDoesNotEstablishFocus() {
        var reducer = CurrentContextReducer()
        reducer.apply(event(.browserTabOpened(tab(connection: UUID()))))
        #expect(reducer.context.browserTab == nil)
    }
    @Test func acceptedBrowserChangesAdvanceTimeWithoutRegressingAcrossSources() {
        var reducer = CurrentContextReducer()
        let page = tab(connection: UUID())
        let latest = Date(timeIntervalSince1970: 20)
        reducer.apply(event(.browserTabActivated(page), at: latest))
        #expect(reducer.context.updatedAt == latest)
        reducer.apply(event(.browserFocusCleared(page.identity.connection), at: Date(timeIntervalSince1970: 10)))
        #expect(reducer.context.browserTab == nil)
        #expect(reducer.context.updatedAt == latest)
        reducer.apply(event(.browserTabOpened(page), at: Date(timeIntervalSince1970: 30)))
        #expect(reducer.context.updatedAt == latest)
    }

    private func tab(connection: UUID) -> BrowserTabContext {
        BrowserTabContext(identity: BrowserTabIdentity(connection: BrowserConnectionIdentity(rawValue: connection), tab: 1),
                          browser: .chrome, window: 2, url: "https://example.com/", domain: "example.com", title: "Example", isActive: true)
    }
    private func event(_ kind: ActivityEventKind, at time: Date = .distantPast) -> ActivityEvent {
        ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: time, source: ActivitySourceID(rawValue: "test"), kind: kind)
    }
}
