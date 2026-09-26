import Darwin
import Foundation
import OSLog
import ThreadDomain

/// Bridges kernel process-exit notifications into terminal session identities on the main run loop.
@MainActor
final class ShellProcessExitObserver {
    private var descriptor: CFFileDescriptor?
    private var runLoopSource: CFRunLoopSource?
    private var registrations: [TerminalSessionIdentity: Int32] = [:]
    private let logger = Logger(subsystem: "app.thread.desktop", category: "shell")
    private let ended: @MainActor (TerminalSessionIdentity) -> Void

    init(ended: @escaping @MainActor (TerminalSessionIdentity) -> Void) { self.ended = ended }

    func watch(_ terminal: TerminalContext) throws {
        let pid = terminal.processIdentifier
        guard registrations[terminal.session] == nil else { return }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_uid == getuid() else {
            throw ShellTransportError.unavailable
        }
        if descriptor == nil { try start() }
        guard let descriptor else { throw ShellTransportError.unavailable }
        guard registrations.count < 256 else { throw ShellTransportError.unavailable }
        var change = kevent(ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ENABLE),
                            fflags: UInt32(NOTE_EXIT), data: 0, udata: nil)
        guard kevent(CFFileDescriptorGetNativeDescriptor(descriptor), &change, 1, nil, 0, nil) == 0 else {
            throw ShellTransportError.unavailable
        }
        registrations[terminal.session] = pid
    }

    func prune(retaining sessions: Set<TerminalSessionIdentity>) {
        for session in Array(registrations.keys) where !sessions.contains(session) { forget(session) }
    }

    func forget(_ session: TerminalSessionIdentity) {
        guard let pid = registrations.removeValue(forKey: session), !registrations.values.contains(pid),
              let descriptor else { return }
        var change = kevent(ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_DELETE), fflags: 0, data: 0, udata: nil)
        if kevent(CFFileDescriptorGetNativeDescriptor(descriptor), &change, 1, nil, 0, nil) < 0,
           errno != ESRCH, errno != ENOENT { logger.error("Shell process registration removal unavailable") }
    }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let descriptor { CFFileDescriptorInvalidate(descriptor) }
        descriptor = nil
        runLoopSource = nil
        registrations.removeAll()
    }

    isolated deinit { stop() }

    private func start() throws {
        let fd = kqueue()
        guard fd >= 0 else { throw ShellTransportError.unavailable }
        guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else { close(fd); throw ShellTransportError.unavailable }
        var context = CFFileDescriptorContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                              retain: nil, release: nil, copyDescription: nil)
        let callback: CFFileDescriptorCallBack = { _, _, info in
            guard let info else { return }
            MainActor.assumeIsolated {
                Unmanaged<ShellProcessExitObserver>.fromOpaque(info).takeUnretainedValue().receive()
            }
        }
        guard let descriptor = CFFileDescriptorCreate(nil, fd, true, callback, &context) else {
            close(fd); throw ShellTransportError.unavailable
        }
        guard let source = CFFileDescriptorCreateRunLoopSource(nil, descriptor, 0) else {
            CFFileDescriptorInvalidate(descriptor); throw ShellTransportError.unavailable
        }
        self.descriptor = descriptor
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CFFileDescriptorEnableCallBacks(descriptor, CFOptionFlags(kCFFileDescriptorReadCallBack))
    }

    private func receive() {
        guard let descriptor else { return }
        var notification = kevent()
        var timeout = timespec(tv_sec: 0, tv_nsec: 0)
        // Drain only when the kernel marks the descriptor readable; never poll for processes.
        for _ in 0..<256 {
            let count = kevent(CFFileDescriptorGetNativeDescriptor(descriptor), nil, 0, &notification, 1, &timeout)
            if count < 0 {
                if errno == EINTR { continue }
                logger.error("Shell process exit observation unavailable")
                stop()
                return
            }
            guard count > 0 else { break }
            guard notification.flags & UInt16(EV_ERROR) == 0, notification.fflags & UInt32(NOTE_EXIT) != 0 else {
                logger.error("Shell process notification rejected")
                continue
            }
            let sessions = registrations.filter { $0.value == Int32(notification.ident) }.map(\.key)
            for session in sessions { forget(session); ended(session) }
        }
        CFFileDescriptorEnableCallBacks(descriptor, CFOptionFlags(kCFFileDescriptorReadCallBack))
    }
}
