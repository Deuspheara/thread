import AppKit
import Carbon

public enum ShortcutError: Error { case registrationFailed }

/// Registers one system hot key without monitoring or retaining typed keystrokes.
@MainActor
public final class SwitcherShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor () -> Void

    public init(action: @escaping @MainActor () -> Void) { self.action = action }

    public func start() throws {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identity = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &identity)
            guard result == noErr, identity.signature == 0x54485244, identity.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            MainActor.assumeIsolated {
                Unmanaged<SwitcherShortcut>.fromOpaque(context).takeUnretainedValue().action()
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { stop(); throw ShortcutError.registrationFailed }
        let identity = EventHotKeyID(signature: 0x54485244, id: 1)
        let registration = RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), identity,
                                              GetApplicationEventTarget(), 0, &hotKey)
        guard registration == noErr else { stop(); throw ShortcutError.registrationFailed }
    }

    public func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    isolated deinit { stop() }
}
