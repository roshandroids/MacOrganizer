import Testing
import Foundation
@testable import OrganizerCore

@Suite("CleanupService")
struct CleanupServiceTests {
    func makeService(trashDir: URL) -> (CleanupService, FakeTrashService) {
        let fake = FakeTrashService(trashDirectory: trashDir)
        return (CleanupService(trashService: fake, policy: .system()), fake)
    }

    @Test func trashesUnkeptDuplicates() async throws {
        let root = try TestFS.makeTempDirectory()
        let trashDir = try TestFS.makeTempDirectory()
        let keep = try TestFS.write("keep.txt", in: root, contents: "dup")
        let extra = try TestFS.write("extra.txt", in: root, contents: "dup")
        let group = try DuplicateGroup(hash: "h", items: [TestFS.item(at: keep), TestFS.item(at: extra)])
        let decision = DuplicateDecision(groupID: "h", keepPaths: [keep])

        let (service, fake) = makeService(trashDir: trashDir)
        let result = await service.trashDuplicates(decisions: [decision], groups: [group])
        #expect(result.errors.isEmpty)
        #expect(result.trashed.map(\.source) == [extra])
        #expect(await fake.calls.count == 1)
        #expect(FileManager.default.fileExists(atPath: keep.path))
        #expect(!FileManager.default.fileExists(atPath: extra.path))
    }

    @Test func refusesToTrashEveryCopyInAGroup() async throws {
        let root = try TestFS.makeTempDirectory()
        let trashDir = try TestFS.makeTempDirectory()
        let a = try TestFS.write("a.txt", in: root, contents: "dup")
        let b = try TestFS.write("b.txt", in: root, contents: "dup")
        let group = try DuplicateGroup(hash: "h", items: [TestFS.item(at: a), TestFS.item(at: b)])
        // Caller mistakenly (or maliciously) marks nothing to keep.
        let decision = DuplicateDecision(groupID: "h", keepPaths: [])

        let (service, fake) = makeService(trashDir: trashDir)
        let result = await service.trashDuplicates(decisions: [decision], groups: [group])
        #expect(!result.errors.isEmpty)
        #expect(result.trashed.isEmpty)
        #expect(await fake.calls.isEmpty)
        #expect(FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: b.path))
    }

    @Test func trashesOldInstallers() async throws {
        let root = try TestFS.makeTempDirectory()
        let trashDir = try TestFS.makeTempDirectory()
        let installer = try TestFS.write("Old.dmg", in: root, modified: TestFS.daysAgo(30))
        let item = try TestFS.item(at: installer)

        let (service, _) = makeService(trashDir: trashDir)
        let result = await service.trashOldInstallers([item])
        #expect(result.errors.isEmpty)
        #expect(result.trashed.count == 1)
        #expect(!FileManager.default.fileExists(atPath: installer.path))
    }

    @Test func emptyFolderCleanupExcludesKeepDirectories() async throws {
        let root = try TestFS.makeTempDirectory()
        let trashDir = try TestFS.makeTempDirectory()
        let keepDir = try TestFS.makeDirectory("Projects/EmptySub", in: root)
        let otherEmpty = try TestFS.makeDirectory("Junk", in: root)

        let candidates = [EmptyFolderCandidate(path: keepDir), EmptyFolderCandidate(path: otherEmpty)]
        let (service, _) = makeService(trashDir: trashDir)
        let result = await service.trashEmptyFolders(candidates, keepDirectories: [root.appendingPathComponent("Projects")])

        #expect(result.trashed.map(\.source) == [otherEmpty])
        #expect(FileManager.default.fileExists(atPath: keepDir.path), "keep-dir folders must never be trashed by cleanup")
    }
}
