import Testing
import Foundation
@testable import OrganizerCore

@Suite("UndoService")
struct UndoServiceTests {
    func run(source: URL, destination: URL, sourceItem: FileItem, createdDirectories: [URL]) -> OperationRun {
        let record = OperationRecord(
            kind: .organizeMove, source: source, destination: destination, trashResultURL: nil,
            sizeBytes: sourceItem.size, identity: sourceItem.identity,
            sourceModificationDate: sourceItem.modificationDate, createdDirectories: createdDirectories
        )
        return OperationRun(root: source.deletingLastPathComponent(), label: "test", records: [record])
    }

    @Test func normalUndoRestoresFileAndRemovesCreatedFolder() async throws {
        let root = try TestFS.makeTempDirectory()
        let service = OrganizationService()
        _ = try TestFS.write("doc.pdf", in: root, modified: TestFS.daysAgo(1))
        let plan = try await service.plan(root: root, byDate: false, dateFormat: .yearMonth, recentlyModifiedMinutes: 10, clock: SystemClock())
        let (records, _) = await service.apply(moves: plan.moves)
        let opRun = OperationRun(root: root, label: "organize", records: records)

        let result = await UndoService().undo(run: opRun)
        #expect(result.restoredCount == 1)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("doc.pdf").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Documents").path), "the category folder undo created should be removed once empty")
    }

    @Test func undoReportsMissingDestination() async throws {
        let root = try TestFS.makeTempDirectory()
        let source = root.appendingPathComponent("doc.pdf")
        let dest = root.appendingPathComponent("Documents/doc.pdf")
        let originalItem = try TestFS.item(at: try TestFS.write("stand-in.pdf", in: root))
        let opRun = run(source: source, destination: dest, sourceItem: originalItem, createdDirectories: [])

        let result = await UndoService().undo(run: opRun)
        #expect(result.restoredCount == 0)
        guard case .skippedMissingDestination = result.outcomes[0] else {
            Issue.record("expected skippedMissingDestination, got \(result.outcomes[0])")
            return
        }
    }

    @Test func undoRefusesWhenSourceIsOccupied() async throws {
        let root = try TestFS.makeTempDirectory()
        let docDir = try TestFS.makeDirectory("Documents", in: root)
        let dest = try TestFS.write("doc.pdf", in: docDir, contents: "moved content")
        let destItem = try TestFS.item(at: dest)
        // Something new now occupies the original source path.
        let source = try TestFS.write("doc.pdf", in: root, contents: "a newer, unrelated file")

        let opRun = run(source: source, destination: dest, sourceItem: destItem, createdDirectories: [])
        let result = await UndoService().undo(run: opRun)
        #expect(result.restoredCount == 0)
        guard case .skippedSourceOccupied = result.outcomes[0] else {
            Issue.record("expected skippedSourceOccupied, got \(result.outcomes[0])")
            return
        }
        // Neither file should have moved or been overwritten.
        #expect(try String(contentsOf: source, encoding: .utf8) == "a newer, unrelated file")
        #expect(try String(contentsOf: dest, encoding: .utf8) == "moved content")
    }

    @Test func undoSkipsFileChangedAtDestination() async throws {
        let root = try TestFS.makeTempDirectory()
        let docDir = try TestFS.makeDirectory("Documents", in: root)
        let originalMoved = try TestFS.write("doc.pdf", in: docDir, contents: "original")
        let originalItem = try TestFS.item(at: originalMoved)
        // The destination file gets replaced in-place (new inode) after the move.
        try FileManager.default.removeItem(at: originalMoved)
        _ = try TestFS.write("doc.pdf", in: docDir, contents: "replaced in place")

        let source = root.appendingPathComponent("doc.pdf")
        let opRun = run(source: source, destination: originalMoved, sourceItem: originalItem, createdDirectories: [])
        let result = await UndoService().undo(run: opRun)
        #expect(result.restoredCount == 0)
        guard case .skippedChanged = result.outcomes[0] else {
            Issue.record("expected skippedChanged, got \(result.outcomes[0])")
            return
        }
    }

    @Test func trashedItemsAreReportedButNotReversed() async throws {
        let root = try TestFS.makeTempDirectory()
        let trashRecord = OperationRecord(
            kind: .trash, source: root.appendingPathComponent("gone.txt"), destination: nil,
            trashResultURL: nil, sizeBytes: 10, identity: FileIdentity(device: 0, inode: 0),
            sourceModificationDate: Date()
        )
        let opRun = OperationRun(root: root, label: "cleanup", records: [trashRecord])
        let result = await UndoService().undo(run: opRun)
        #expect(result.outcomes.isEmpty)
        #expect(result.unreversedTrashedCount == 1)
    }
}
