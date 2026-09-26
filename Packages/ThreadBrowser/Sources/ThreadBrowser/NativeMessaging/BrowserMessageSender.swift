import Darwin
import Foundation

/// Sends a bounded metadata datagram without waiting for the application to start.
public struct BrowserMessageSender {
    public init() {}

    func isAvailable(at url: URL) -> Bool {
        guard (try? validateDestination(url)) != nil, let address = try? UnixSocketAddress(path: url.path) else { return false }
        let descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        return address.data.withUnsafeBytes { bytes in
            Darwin.connect(descriptor, bytes.baseAddress?.assumingMemoryBound(to: sockaddr.self), socklen_t(bytes.count)) == 0
        }
    }

    private func validateDestination(_ url: URL) throws -> String {
        var directory = stat()
        var endpoint = stat()
        guard lstat(url.deletingLastPathComponent().path, &directory) == 0,
              directory.st_mode & S_IFMT == S_IFDIR, directory.st_uid == getuid(), directory.st_mode & 0o077 == 0,
              lstat(url.path, &endpoint) == 0, endpoint.st_mode & S_IFMT == S_IFSOCK,
              endpoint.st_uid == getuid(), endpoint.st_mode & 0o077 == 0 else { throw BrowserTransportError.unsafeDirectory }
        return "\(endpoint.st_dev):\(endpoint.st_ino):\(endpoint.st_birthtimespec.tv_sec):\(endpoint.st_birthtimespec.tv_nsec)"
    }

    @discardableResult
    public func send(_ message: BrowserMessage, to url: URL = BrowserSocketLocation.defaultURL) throws -> String? {
        guard let safe = try message.sanitized() else { return nil }
        let data = try JSONEncoder().encode(safe)
        return try sendControl(data, to: url)
    }

    @discardableResult
    func sendControl(_ data: Data, to url: URL) throws -> String {
        guard data.count <= 8192 else { throw BrowserTransportError.invalidMessage }
        let instance = try validateDestination(url)
        let address = try UnixSocketAddress(path: url.path)
        let descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { throw BrowserTransportError.unavailable }
        defer { close(descriptor) }
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else { throw BrowserTransportError.unavailable }
        let count = address.data.withUnsafeBytes { socketBytes in
            data.withUnsafeBytes { payload in
                sendto(descriptor, payload.baseAddress, payload.count, 0,
                       socketBytes.baseAddress?.assumingMemoryBound(to: sockaddr.self), socklen_t(socketBytes.count))
            }
        }
        guard count == data.count else { throw BrowserTransportError.sendFailed }
        return instance
    }
}
