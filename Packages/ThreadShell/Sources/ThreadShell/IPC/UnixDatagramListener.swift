import Darwin
import Foundation

/// Delivers Unix datagrams through a main-run-loop C API bridge without polling.
@MainActor
final class UnixDatagramListener {
    private var socket: CFSocket?
    private var runLoopSource: CFRunLoopSource?
    private var lease: SocketDirectoryLease?
    private let receive: @MainActor (Data) -> Void

    init(receive: @escaping @MainActor (Data) -> Void) { self.receive = receive }

    func start(at url: URL) throws {
        guard socket == nil else { return }
        let address = try UnixSocketAddress(path: url.path)
        let lease = try SocketDirectoryLease(socketURL: url)
        var context = CFSocketContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                      retain: nil, release: nil, copyDescription: nil)
        let callback: CFSocketCallBack = { _, _, _, data, info in
            guard let data, let info else { return }
            let bytes = Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue() as Data
            MainActor.assumeIsolated {
                Unmanaged<UnixDatagramListener>.fromOpaque(info).takeUnretainedValue().receive(bytes)
            }
        }
        guard let created = CFSocketCreate(nil, AF_UNIX, SOCK_DGRAM, 0, CFSocketCallBackType.dataCallBack.rawValue,
                                            callback, &context) else { throw ShellTransportError.unavailable }
        let descriptor = CFSocketGetNative(created)
        // CFSocketSetAddress also calls listen(), which is invalid for datagram sockets.
        let bound = address.data.withUnsafeBytes { bytes in
            Darwin.bind(descriptor, bytes.baseAddress?.assumingMemoryBound(to: sockaddr.self), socklen_t(bytes.count))
        }
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0, bound == 0 else {
            CFSocketInvalidate(created)
            throw ShellTransportError.unavailable
        }
        guard chmod(url.path, 0o600) == 0, let source = CFSocketCreateRunLoopSource(nil, created, 0) else {
            CFSocketInvalidate(created)
            unlink(url.path)
            throw ShellTransportError.unavailable
        }
        self.lease = lease
        socket = created
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    isolated deinit { stop() }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let socket { CFSocketInvalidate(socket) }
        socket = nil
        runLoopSource = nil
        if let lease { unlink(lease.path) }
        lease = nil
    }
}
