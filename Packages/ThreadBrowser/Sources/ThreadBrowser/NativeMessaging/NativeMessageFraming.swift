import Foundation

/// Reads and writes Chromium's length-prefixed JSON frames with bounded allocation and partial-read support.
public struct NativeMessageFraming {
    public init() {}
    public func read(from input: FileHandle) throws -> Data? {
        guard let header = try readExactly(4, from: input, allowEOF: true) else { return nil }
        let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard length > 0, length <= 16_384 else { throw BrowserTransportError.invalidFrame }
        return try readExactly(Int(length), from: input, allowEOF: false)
    }
    public func write(_ data: Data, to output: FileHandle) throws {
        guard !data.isEmpty, data.count <= 16_384 else { throw BrowserTransportError.invalidFrame }
        var length = UInt32(data.count)
        try withUnsafeBytes(of: &length) { try output.write(contentsOf: $0) }
        try output.write(contentsOf: data)
    }
    private func readExactly(_ count: Int, from input: FileHandle, allowEOF: Bool) throws -> Data? {
        var result = Data()
        while result.count < count {
            guard let bytes = try input.read(upToCount: count - result.count), !bytes.isEmpty else {
                if allowEOF && result.isEmpty { return nil }
                throw BrowserTransportError.invalidFrame
            }
            result.append(bytes)
        }
        return result
    }
}
