import Foundation
import Testing
@testable import ThreadBrowser

struct NativeFramingTests {
    @Test func roundTripMultipleFramesAndEOF() throws {
        let pipe = Pipe()
        let framing = NativeMessageFraming()
        try framing.write(Data("{\"ok\":true}".utf8), to: pipe.fileHandleForWriting)
        try framing.write(Data("{}".utf8), to: pipe.fileHandleForWriting)
        pipe.fileHandleForWriting.closeFile()
        defer { pipe.fileHandleForReading.closeFile() }
        #expect(try framing.read(from: pipe.fileHandleForReading) == Data("{\"ok\":true}".utf8))
        #expect(try framing.read(from: pipe.fileHandleForReading) == Data("{}".utf8))
        #expect(try framing.read(from: pipe.fileHandleForReading) == nil)
    }

    @Test func oversizedAndTruncatedFramesFailWithoutUnboundedReads() throws {
        for bytes in [Data([255,255,255,127]), Data([3,0,0,0,1]), Data([1,0])] {
            let pipe = Pipe()
            try pipe.fileHandleForWriting.write(contentsOf: bytes)
            pipe.fileHandleForWriting.closeFile()
            defer { pipe.fileHandleForReading.closeFile() }
            #expect(throws: (any Error).self) { try NativeMessageFraming().read(from: pipe.fileHandleForReading) }
        }
    }
}
