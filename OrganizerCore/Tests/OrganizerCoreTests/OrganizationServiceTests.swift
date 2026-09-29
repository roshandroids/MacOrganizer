import Testing
import Foundation
@testable import OrganizerCore

@Suite("OrganizationService")
struct OrganizationServiceTests {
    @Test func skipsRecentlyModifiedFiles() async throws {
        let root = try TestFS.makeTempDirectory()
        try TestFS.write("old.txt", in: root, modified: TestFS.daysAgo(1))
        try TestFS.write("brandnew.txt", in: root, modified: Date())

        let plan = try await OrganizationService().plan(
            root: root, byDate: false, dateFormat: .yearMonth,
            recentlyModifiedMinutes: 10, clock: SystemClock()
        )
        let names = Set(plan.moves.map(\.source.path.lastPathComponent))
        #expect(names.contains("old.txt"))
        #expect(!names.contains("brandnew.txt"))
        #expect(plan.skippedCount == 1)
    }

    @Test func skipsInProgressDownloads() async throws {
        let root = try TestFS.makeTempDirectory()
        try TestFS.write("movie.mp4.crdownload", in: root, modified: TestFS.daysAgo(1))
        try TestFS.write("done.mp4", in: root, modified: TestFS.daysAgo(1))

        let plan = try await OrganizationService().plan(
            root: root, byDate: false, dateFormat: .yearMonth,
            recentlyModifiedMinutes: 10, clock: SystemClock()
        )
        let names = Set(plan.moves.map(\.source.path.lastPathComponent))
        #expect(names.contains("done.mp4"))
        #expect(!names.contains("movie.mp4.crdownload"))
    }

    @Test func directoriesAreNeverPlannedAsMoves() async throws {
        let root = try TestFS.makeTempDirectory()
        _ = try TestFS.makeDirectory("SomeFolder", in: root)
        try TestFS.write("file.txt", in: root, modified: TestFS.daysAgo(1))

        let plan = try await OrganizationService().plan(
            root: root, byDate: false, dateFormat: .yearMonth,
            recentlyModifiedMinutes: 10, clock: SystemClock()
        )
        #expect(plan.moves.count == 1)
        #expect(plan.moves[0].source.path.lastPathComponent == "file.txt")
    }

    @Test func byDatePlacesFilesInYearMonthSubfolder() async throws {
        let root = try TestFS.makeTempDirectory()
        let date = TestFS.daysAgo(400)
        try TestFS.write("photo.jpg", in: root, modified: date)

        let plan = try await OrganizationService().plan(
            root: root, byDate: true, dateFormat: .yearMonth,
            recentlyModifiedMinutes: 10, clock: SystemClock()
        )
        let move = try #require(plan.moves.first)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let expectedComponent = formatter.string(from: date)
        #expect(move.destination.path.contains("Images/\(expectedComponent)/photo.jpg"))
    }

    @Test func planningReservesUniqueNamesForCollisions() async throws {
        let root = try TestFS.makeTempDirectory()
        try TestFS.write("Images/photo.jpg", in: root, contents: "existing")
        try TestFS.write("photo.jpg", in: root, contents: "new-one", modified: TestFS.daysAgo(1))

        let plan = try await OrganizationService().plan(
            root: root, byDate: false, dateFormat: .yearMonth,
            recentlyModifiedMinutes: 10, clock: SystemClock()
        )
        let move = try #require(plan.moves.first { $0.source.path.lastPathComponent == "photo.jpg" })
        #expect(move.destination.lastPathComponent == "photo (1).jpg")
    }

    @Test func applyMovesFilesAndCreatesCategoryFolders() async throws {
        let root = try TestFS.makeTempDirectory()
        try TestFS.write("doc.pdf", in: root, modified: TestFS.daysAgo(1))

        let service = OrganizationService()
        let plan = try await service.plan(
            root: root, byDate: false, dateFormat: .yearMonth,
            recentlyModifiedMinutes: 10, clock: SystemClock()
        )
        let (records, errors) = await service.apply(moves: plan.moves)
        #expect(errors.isEmpty)
        #expect(records.count == 1)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Documents/doc.pdf").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("doc.pdf").path))
    }

    @Test func applySkipsFileThatChangedSincePreview() async throws {
        let root = try TestFS.makeTempDirectory()
        let url = try TestFS.write("doc.pdf", in: root, modified: TestFS.daysAgo(1))
        let staleItem = try TestFS.item(at: url)

        // Simulate the file changing after Preview was generated.
        try "changed contents!!".write(to: url, atomically: true, encoding: .utf8)

        let move = PlannedMove(source: staleItem, category: .documents, destination: root.appendingPathComponent("Documents/doc.pdf"))
        let (records, errors) = await OrganizationService().apply(moves: [move])
        #expect(records.isEmpty)
        #expect(errors.count == 1)
        #expect(errors[0].contains("changed"))
        // File must still be at its original location, untouched.
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func applySkipsFileThatNoLongerExists() async throws {
        let root = try TestFS.makeTempDirectory()
        let url = try TestFS.write("doc.pdf", in: root, modified: TestFS.daysAgo(1))
        let item = try TestFS.item(at: url)
        try FileManager.default.removeItem(at: url)

        let move = PlannedMove(source: item, category: .documents, destination: root.appendingPathComponent("Documents/doc.pdf"))
        let (records, errors) = await OrganizationService().apply(moves: [move])
        #expect(records.isEmpty)
        #expect(errors.count == 1)
        #expect(errors[0].contains("no longer exists"))
    }
}
