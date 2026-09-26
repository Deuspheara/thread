import Darwin
import Foundation

/// Encodes a filesystem Unix address after checking the platform's byte limit.
struct UnixSocketAddress {
    let data: Data

    init(path: String) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard path.hasPrefix("/"), !path.utf8.contains(0),
              bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw ShellTransportError.invalidPath }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        // Darwin SUN_LEN excludes the trailing NUL and unused path capacity.
        let length = MemoryLayout<sockaddr_un>.size - MemoryLayout.size(ofValue: address.sun_path) + bytes.count - 1
        address.sun_len = UInt8(length)
        data = withUnsafeBytes(of: &address) { Data($0.prefix(length)) }
    }
}
