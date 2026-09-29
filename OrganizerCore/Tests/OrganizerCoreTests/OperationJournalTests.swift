import Testing
import Foundation
@testable import OrganizerCore

@Suite("OperationJournal")
struct OperationJournalTests {
    @Test func recordsPersistAcrossReload() async throws {
        let dir = try TestFS.makeTempDirectory()
        let journal = try OperationJournal(directory: dir)
        let root = try TestFS.makeTempDirectory()
        let runID = try await journal.beginRun(root: root, label: "Organize")

        let record = OperationRecord(
            kind: .organizeMove, source: root.appendingPathComponent("a.txt"),
            destination: root.appendingPathComponent("Documents/a.txt"), trashResultURL: nil,
            sizeBytes: 10, identity: FileIdentity(device: 1, inode: 2), sourceModificationDate: Date()
        )
        try await journal.append(record, toRun: runID)
        try await journal.finish(runID: runID)

        let loaded = try await journal.load(runID)
        #expect(loaded.records.count == 1)
        #expect(loaded.finishedAt != nil)
        #expect(loaded.label == "Organize")
    }

    @Test func listRunsReturnsNewestFirst() async throws {
        let dir = try TestFS.makeTempDirectory()
        let journal = try OperationJournal(directory: dir)
        let root = try TestFS.makeTempDirectory()
        _ = try await journal.beginRun(root: root, label: "First")
        try await Task.sleep(nanoseconds: 50_000_000)
        _ = try await journal.beginRun(root: root, label: "Second")

        let runs = await journal.listRuns()
        #expect(runs.count == 2)
        #expect(runs.first?.label == "Second")
    }
}
