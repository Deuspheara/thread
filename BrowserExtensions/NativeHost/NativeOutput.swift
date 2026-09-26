import Foundation
import ThreadBrowser

/// Serializes observation acknowledgments and restore commands on framed native stdout.
actor NativeOutput {
    private let framing = NativeMessageFraming()
    func write(_ data: Data) throws { try framing.write(data, to: .standardOutput) }
}
