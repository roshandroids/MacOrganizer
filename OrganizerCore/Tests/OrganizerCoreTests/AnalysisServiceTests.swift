import Testing
import Foundation
@testable import OrganizerCore

@Suite("AnalysisService")
struct AnalysisServiceTests {
    func options(keepDirectories: [URL] = []) -> AnalysisOptions {
        AnalysisOptions(
            largeFileThresholdBytes: 100 * 1024 * 1024, oldFileThresholdDays: 180,
            oldInstallerThresholdDays: 14, recentlyModifiedMinutes: 10, keepDirectories: keepDirectories
        )
    }

    @Test func flagsOldFiles() async throws {
        let root = try TestFS.makeTempDirectory()
        try TestFS.write("ancient.txt", in: root, modified: TestFS.daysAgo(200))
        try TestFS.write("recentish.txt", in: root, modified: TestFS.daysAgo(5))

        let report = await AnalysisService().analyze(root: root, options: options(), clock: SystemClock())
        let names = Set(report.oldFiles.map(\.path.lastPathComponent))
        #expect(names.contains("ancient.txt"))
        #expect(!names.contains("recentish.txt"))
    }

    @Test func flagsOldInstallersOnly() async throws {
        let root = try TestFS.makeTempDirectory()
        try TestFS.write("Installer.dmg", in: root, modified: TestFS.daysAgo(30))
        try TestFS.write("archive.zip", in: root, modified: TestFS.daysAgo(30))

        let report = await AnalysisService().analyze(root: root, options: options(), clock: SystemClock())
        let names = Set(report.oldInstallers.map(\.path.lastPathComponent))
        #expect(names.contains("Installer.dmg"))
        #expect(!names.contains("archive.zip"), "not every archive is an installer")
    }

    @Test func oldFileDetectionSkipsRecentlyModifiedAndInProgress() async throws {
        // Deliberate deviation from organize_mac.py: the "old" bucket must not
        // include a file that's still downloading or was just touched, even if
        // its extension/size would otherwise qualify.
        let root = try TestFS.makeTempDirectory()
        try TestFS.write("stale.dmg.crdownload", in: root, modified: TestFS.daysAgo(30))

        let report = await AnalysisService().analyze(root: root, options: options(), clock: SystemClock())
        #expect(report.oldInstallers.isEmpty)
    }

    @Test func keepDirFilesAreExcludedFromOldFiles() async throws {
        let root = try TestFS.makeTempDirectory()
        let keepDir = try TestFS.makeDirectory("Projects", in: root)
        try TestFS.write("important.txt", in: keepDir, modified: TestFS.daysAgo(400))

        let report = await AnalysisService().analyze(root: root, options: options(keepDirectories: [keepDir]), clock: SystemClock())
        #expect(report.oldFiles.isEmpty)
    }

    @Test func archiveFolderIsExcludedFromOldFiles() async throws {
        let root = try TestFS.makeTempDirectory()
        try TestFS.write("_Archive/2020/Documents/old.pdf", in: root, modified: TestFS.daysAgo(400))

        let report = await AnalysisService().analyze(root: root, options: options(), clock: SystemClock())
        #expect(report.oldFiles.isEmpty)
    }

    @Test func emptyFoldersAreDetectedTopMostOnly() async throws {
        let root = try TestFS.makeTempDirectory()
        _ = try TestFS.makeDirectory("Empty/Nested", in: root)

        let empties = AnalysisService.findEmptyFolders(root: root)
        #expect(empties.count == 1)
        #expect(empties[0].path.lastPathComponent == "Empty")
    }

    @Test func folderWithOnlyDSStoreCountsAsEmpty() async throws {
        let root = try TestFS.makeTempDirectory()
        try TestFS.write("Junk/.DS_Store", in: root, contents: "")

        let empties = AnalysisService.findEmptyFolders(root: root)
        #expect(empties.contains { $0.path.lastPathComponent == "Junk" })
    }

    @Test func folderWithRealFileIsNotEmpty() async throws {
        let root = try TestFS.makeTempDirectory()
        try TestFS.write("NotEmpty/keep.txt", in: root)

        let empties = AnalysisService.findEmptyFolders(root: root)
        #expect(!empties.contains { $0.path.lastPathComponent == "NotEmpty" })
    }
}
