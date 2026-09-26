import Darwin
import Foundation

/// Sends a bounded metadata datagram without waiting for the application to start.
public struct ShellMessageSender {
    public init() {}

    private func validateDestination(_ url: URL) throws {
        var directory = stat()
        var endpoint = stat()
        guard lstat(url.deletingLastPathComponent().path, &directory) == 0,
              directory.st_mode & S_IFMT == S_IFDIR, directory.st_uid == getuid(), directory.st_mode & 0o077 == 0,
              lstat(url.path, &endpoint) == 0, endpoint.st_mode & S_IFMT == S_IFSOCK,
              endpoint.st_uid == getuid(), endpoint.st_mode & 0o077 == 0 else { throw ShellTransportError.unsafeDirectory }
    }

    public func send(_ message: ShellMessage, to url: URL = ShellSocketLocation.defaultURL) throws {
        let data = try JSONEncoder().encode(message.validated())
        guard data.count <= 8192 else { throw ShellTransportError.invalidMessage }
        try validateDestination(url)
        let address = try UnixSocketAddress(path: url.path)
        let descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { throw ShellTransportError.unavailable }
        defer { close(descriptor) }
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else { throw ShellTransportError.unavailable }
        let count = address.data.withUnsafeBytes { socketBytes in
            data.withUnsafeBytes { payload in
                sendto(descriptor, payload.baseAddress, payload.count, 0,
                       socketBytes.baseAddress?.assumingMemoryBound(to: sockaddr.self), socklen_t(socketBytes.count))
            }
        }
        guard count == data.count else { throw ShellTransportError.sendFailed }
    }
}
