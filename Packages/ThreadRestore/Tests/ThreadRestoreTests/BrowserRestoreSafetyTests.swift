import Testing
@testable import ThreadRestore

struct BrowserRestoreSafetyTests {
    @Test func onlyPublicSanitizedWebResourcesCanBeOpened() {
        let restorer = BrowserRestorer()
        #expect(restorer.safeURL("https://example.com/docs") != nil)
        for raw in ["file:///etc/passwd", "javascript:alert(1)", "https://user:secret@example.com/", "https://example.com/?token=secret", "https://example.com/#secret", "https:///", "terminal://run"] {
            #expect(restorer.safeURL(raw) == nil)
        }
    }
}
