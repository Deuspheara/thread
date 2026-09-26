import Testing
@testable import ThreadMacOS

struct LocalDocumentIdentityTests {
    @Test func acceptsOnlyLocalDocumentMetadata() {
        let reader = LocalDocumentIdentity()
        #expect(reader.file("file:///Users/test/project%20name/main.swift")?.path == "/Users/test/project name/main.swift")
        for raw in ["https://example.com/secret", "file://server/private/file", "file:///tmp/file?secret=1", "file:///tmp/file#secret", "/tmp/file", "file:///tmp/a%00b"] {
            #expect(reader.file(raw) == nil)
        }
        #expect(reader.file(nil) == nil)
    }
}
