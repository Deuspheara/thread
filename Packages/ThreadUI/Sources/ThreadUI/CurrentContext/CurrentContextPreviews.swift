import Foundation
import SwiftUI
import ThreadDomain

#Preview("Permission required") {
    CurrentContextView(model: CurrentContextModel(
        context: CurrentContext(permission: .notGranted, windowAvailability: .permissionRequired),
        prepareStorage: {}, refreshObservation: {}, requestAuthorization: {}, openAuthorizationSettings: { true }
    ))
}

#Preview("Focused window") {
    let app = ApplicationContext(identity: ApplicationIdentity(bundleIdentifier: "com.apple.dt.Xcode"), name: "Xcode", processIdentifier: 42)
    let window = WindowContext(
        identity: WindowIdentity(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
        application: app,
        title: "DeviceSessionCoordinator.swift",
        frame: WindowFrame(x: 40, y: 80, width: 1200, height: 800)
    )
    CurrentContextView(model: CurrentContextModel(
        context: CurrentContext(application: app, window: window, permission: .granted, windowAvailability: .available),
        prepareStorage: {}, refreshObservation: {}, requestAuthorization: {}, openAuthorizationSettings: { true }
    ))
}
