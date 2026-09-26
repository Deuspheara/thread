import Darwin
import Foundation

/// Validates private filesystem ownership and exclusively leases a listener path.
final class SocketDirectoryLease {
    private let lockDescriptor: Int32
    let path: String

    init(socketURL: URL) throws {
        let directory = socketURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        } catch { throw ShellTransportError.unsafeDirectory }
        var directoryInfo = stat()
        guard lstat(directory.path, &directoryInfo) == 0,
              directoryInfo.st_mode & S_IFMT == S_IFDIR,
              directoryInfo.st_uid == getuid(), directoryInfo.st_mode & 0o077 == 0 else {
            throw ShellTransportError.unsafeDirectory
        }
        let descriptor = open(directory.appendingPathComponent("listener.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ShellTransportError.unavailable }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o077 == 0 else {
            close(descriptor)
            throw ShellTransportError.unsafeDirectory
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw ShellTransportError.alreadyListening
        }
        do { try Self.removeStaleSocket(at: socketURL.path) }
        catch { close(descriptor); throw error }
        path = socketURL.path
        lockDescriptor = descriptor
    }

    deinit { close(lockDescriptor) }

    private static func removeStaleSocket(at path: String) throws {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            guard errno == ENOENT else { throw ShellTransportError.unavailable }
            return
        }
        guard info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == getuid(), unlink(path) == 0 else {
            throw ShellTransportError.unsafeDirectory
        }
    }
}
