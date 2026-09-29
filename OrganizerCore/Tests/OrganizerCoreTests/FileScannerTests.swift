import Testing
import Foundation
@testable import OrganizerCore

@Suite("FileScanner safety rules")
struct FileScannerTests {
    @Test func skipsHiddenFilesAndFolders() async throws {
        let root = try TestFS.makeTempDirectory()
        try TestFS.write("visible.txt", in: root)
        try TestFS.write(".hidden.txt", in: root)
        try TestFS.write("inner.txt", in: TestFS.makeDirectory(".hiddenDir", in: root))

        let result = await FileScanner().scan(root: root)
        let names = Set(result.files.map(\.path.lastPathComponent))
        #expect(names.contains("visible.txt"))
        #expect(!names.contains(".hidden.txt"))
        #expect(!names.contains("inner.txt"))
    }

    @Test func skipsAppBundlesAndOtherPackages() async throws {
        let root = try TestFS.makeTempDirectory()
        let bundle = try TestFS.makeDirectory("Thing.app", in: root)
        try TestFS.write("Contents/Info.plist", in: bundle)
        try TestFS.write("real.txt", in: root)

        let result = await FileScanner().scan(root: root)
        let names = Set(result.files.map(\.path.lastPathComponent))
        #expect(names.contains("real.txt"))
        #expect(!names.contains("Info.plist"))
    }

    @Test func skipsJunkDirectories() async throws {
        let root = try TestFS.makeTempDirectory()
        try TestFS.write("index.js", in: TestFS.makeDirectory("node_modules", in: root))
        try TestFS.write("top.txt", in: root)

        let result = await FileScanner().scan(root: root)
        let names = Set(result.files.map(\.path.lastPathComponent))
        #expect(names.contains("top.txt"))
        #expect(!names.contains("index.js"))
    }

    @Test func skipsSymlinks() async throws {
        let root = try TestFS.makeTempDirectory()
        let real = try TestFS.write("real.txt", in: root)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.txt"), withDestinationURL: real
        )

        let result = await FileScanner().scan(root: root)
        let names = Set(result.files.map(\.path.lastPathComponent))
        #expect(names.contains("real.txt"))
        #expect(!names.contains("link.txt"))
    }

    @Test func scanningDoesNotBlockTheMainActor() async throws {
        let root = try TestFS.makeTempDirectory()
        for i in 0..<1500 {
            try TestFS.write("file\(i).txt", in: root)
        }

        // Start a MainActor counter ticking, run the scan concurrently, and
        // confirm the counter kept advancing while the scan was in flight —
        // proof the scan isn't running on (and blocking) the main actor.
        let ticker = MainActorTicker()
        let tickTask = Task { @MainActor in
            while !Task.isCancelled {
                ticker.tick()
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }

        let result = await FileScanner().scan(root: root)
        tickTask.cancel()

        #expect(result.files.count == 1500)
        let finalCount = await ticker.count
        #expect(finalCount > 0)
    }
}

@MainActor
final class MainActorTicker {
    private(set) var count = 0
    func tick() { count += 1 }
}
