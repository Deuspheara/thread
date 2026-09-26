import Testing
import ThreadDomain
@testable import ThreadUI

@MainActor
struct LoginLaunchModelTests {
    @Test func failedChangeDisplaysActualSystemState() {
        enum Rejected: Error { case denied }
        let model = LoginLaunchModel(readStatus: { .disabled },
                                     change: { _ in throw Rejected.denied }, showSettings: {})
        model.refresh()
        model.setEnabled(true)
        #expect(model.changeFailed)
        #expect(!model.isRequested)
        #expect(model.status == .disabled)
    }

    @Test func pendingApprovalRemainsRequestedAndExternalChangesRefresh() {
        var systemState: LoginLaunchStatus = .requiresApproval
        let model = LoginLaunchModel(readStatus: { systemState },
                                     change: { enabled in systemState = enabled ? .requiresApproval : .disabled },
                                     showSettings: {})
        model.refresh()
        #expect(model.isRequested)
        model.setEnabled(false)
        #expect(!model.isRequested)
        #expect(!model.changeFailed)
        systemState = .enabled
        model.refresh()
        #expect(model.status == .enabled)
    }
}
