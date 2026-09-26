import Foundation
import Testing
import ThreadDomain
@testable import ThreadUI

@MainActor
struct ThreadSplitModelTests {
    @Test func unsavedSuccessfulSplitCannotBeSubmittedTwice() async {
        let time = Date(timeIntervalSince1970: 100)
        let resources = [Resource.workingDirectory("/original"), .file(FileIdentity(path: "/original/separate.swift"))].map {
            ThreadResource(resource: $0, confidence: 0.98, firstSeen: time, lastSeen: time,
                           source: ActivitySourceID(rawValue: "fixture"), status: .confirmed)
        }
        let source = ThreadDetail(thread: ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: "Original",
                                                               createdAt: time, lastActiveAt: time), resources: resources)
        let edits = UnsavedSplitEdits()
        let model = ThreadSplitModel(source: source, totalResourceCount: resources.count, editing: edits)
        model.title = "Separate"
        model.select(resources[0].resource.id, included: true)
        await model.save()
        await model.save()
        #expect(model.complete)
        #expect(!model.canSplit)
        #expect(model.message?.contains("not saved") == true)
        #expect(await edits.count == 1)
    }
}

private actor UnsavedSplitEdits: ThreadEditing {
    private(set) var count = 0
    func edit(_ edit: ThreadEdit) async throws -> HistoryStatus { count += 1; return .unsaved }
}
