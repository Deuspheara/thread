import ApplicationServices
import Foundation
import ThreadDomain

/// Keeps bounded session identities for observed windows without exposing AX references to the core.
@MainActor
final class WindowIdentityRegistry {
    private struct Entry {
        let element: AXUIElement
        let application: ApplicationContext
        let identity: WindowIdentity
    }
    private var entries: [Entry] = []

    func identity(for element: AXUIElement, application: ApplicationContext) -> WindowIdentity {
        if let index = entries.firstIndex(where: { $0.application.isSameInstance(as: application) && CFEqual($0.element, element) }) {
            let entry = entries.remove(at: index)
            entries.append(entry)
            return entry.identity
        }
        let identity = WindowIdentity(rawValue: UUID())
        entries.append(Entry(element: element, application: application, identity: identity))
        if entries.count > 256 { entries.removeFirst() }
        return identity
    }

    func remove(_ element: AXUIElement) {
        entries.removeAll { CFEqual($0.element, element) }
    }

    func remove(processIdentifier: Int32) {
        entries.removeAll { $0.application.processIdentifier == processIdentifier }
    }
}
