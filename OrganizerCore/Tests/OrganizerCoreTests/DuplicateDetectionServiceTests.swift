import Testing
import Foundation
@testable import OrganizerCore

@Suite("DuplicateDetectionService")
struct DuplicateDetectionServiceTests {
    @Test func identicalFilesAreGrouped() async throws {
        let root = try TestFS.makeTempDirectory()
        let a = try TestFS.write("a.txt", in: root, contents: "same content")
        let b = try TestFS.write("b.txt", in: root, contents: "same content")

        let files = try [TestFS.item(at: a), TestFS.item(at: b)]
        let result = await DuplicateDetectionService().findDuplicates(in: files)
        #expect(result.groups.count == 1)
        #expect(result.groups[0].items.count == 2)
    }

    @Test func sameFilenameDifferentContentsIsNotADuplicate() async throws {
        let rootA = try TestFS.makeTempDirectory()
        let rootB = try TestFS.makeTempDirectory()
        let a = try TestFS.write("report.pdf", in: rootA, contents: "version one")
        let b = try TestFS.write("report.pdf", in: rootB, contents: "version two, longer content")

        let files = try [TestFS.item(at: a), TestFS.item(at: b)]
        let result = await DuplicateDetectionService().findDuplicates(in: files)
        #expect(result.groups.isEmpty)
    }

    @Test func differentFilenameSameContentIsADuplicate() async throws {
        let root = try TestFS.makeTempDirectory()
        let a = try TestFS.write("original.txt", in: root, contents: "identical bytes")
        let b = try TestFS.write("totally-different-name.txt", in: root, contents: "identical bytes")

        let files = try [TestFS.item(at: a), TestFS.item(at: b)]
        let result = await DuplicateDetectionService().findDuplicates(in: files)
        #expect(result.groups.count == 1)
    }

    @Test func sameSizeDifferentContentsIsNotADuplicate() async throws {
        let root = try TestFS.makeTempDirectory()
        let a = try TestFS.write("a.txt", in: root, contents: "AAAAAAAAAA")
        let b = try TestFS.write("b.txt", in: root, contents: "BBBBBBBBBB")

        let files = try [TestFS.item(at: a), TestFS.item(at: b)]
        let result = await DuplicateDetectionService().findDuplicates(in: files)
        #expect(result.groups.isEmpty)
    }

    @Test func hardLinkedFilesAreNotReportedAsDuplicates() async throws {
        let root = try TestFS.makeTempDirectory()
        let a = try TestFS.write("original.txt", in: root, contents: "shared bytes")
        let linked = root.appendingPathComponent("hardlink.txt")
        try FileManager.default.linkItem(at: a, to: linked)

        let files = try [TestFS.item(at: a), TestFS.item(at: linked)]
        let result = await DuplicateDetectionService().findDuplicates(in: files)
        #expect(result.groups.isEmpty, "hard-linked paths share one identity — not a duplicate set")
    }

    @Test func emptyFilesAreNeverGroupedAsDuplicates() async throws {
        let root = try TestFS.makeTempDirectory()
        let a = try TestFS.write("empty1.txt", in: root, contents: "")
        let b = try TestFS.write("empty2.txt", in: root, contents: "")

        let files = try [TestFS.item(at: a), TestFS.item(at: b)]
        let result = await DuplicateDetectionService().findDuplicates(in: files)
        #expect(result.groups.isEmpty)
    }
}

@Suite("DuplicateSelection")
struct DuplicateSelectionTests {
    @Test func prefersNonCopyLookingName() throws {
        let root = try TestFS.makeTempDirectory()
        let original = try TestFS.write("report.pdf", in: root, contents: "x", modified: TestFS.daysAgo(1))
        let copy = try TestFS.write("report (1).pdf", in: root, contents: "x", modified: TestFS.daysAgo(1))
        let group = try [TestFS.item(at: original), TestFS.item(at: copy)]

        let keeper = DuplicateSelection.pickKeeper(group)
        #expect(keeper.path == original)
    }

    @Test func keepDirCopiesAreAlwaysSuggestedKeepers() throws {
        let root = try TestFS.makeTempDirectory()
        let keepDir = try TestFS.makeDirectory("Projects", in: root)
        let protectedCopy = try TestFS.write("file.txt", in: keepDir, contents: "x")
        let looseCopy = try TestFS.write("file.txt", in: root, contents: "x")
        let group = try [TestFS.item(at: protectedCopy), TestFS.item(at: looseCopy)]

        let policy = PathPolicy(homeDirectory: root, protectedExactPaths: [], protectedSubtreeRoots: [])
        let keepers = DuplicateSelection.defaultKeepers(group, keepDirectories: [keepDir], policy: policy)
        #expect(keepers == [protectedCopy])
    }
}
