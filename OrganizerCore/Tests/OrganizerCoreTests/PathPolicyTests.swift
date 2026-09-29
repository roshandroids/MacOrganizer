import Testing
import Foundation
@testable import OrganizerCore

@Suite("Protected paths")
struct PathPolicyTests {
    func makePolicy(home: URL) -> PathPolicy {
        PathPolicy(
            homeDirectory: home,
            protectedExactPaths: [URL(fileURLWithPath: "/"), home, URL(fileURLWithPath: "/Users")],
            protectedSubtreeRoots: [
                home.appendingPathComponent("Library"),
                URL(fileURLWithPath: "/System"),
                URL(fileURLWithPath: "/Library"),
                URL(fileURLWithPath: "/Applications"),
                URL(fileURLWithPath: "/usr"),
            ]
        )
    }

    @Test func rootIsProtected() {
        let policy = makePolicy(home: URL(fileURLWithPath: "/Users/tester"))
        #expect(policy.isProtectedRoot(URL(fileURLWithPath: "/")))
    }

    @Test func homeItselfIsProtected() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let policy = makePolicy(home: home)
        #expect(policy.isProtectedRoot(home))
    }

    @Test func homeLibraryIsProtected() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let policy = makePolicy(home: home)
        #expect(policy.isProtectedRoot(home.appendingPathComponent("Library")))
        #expect(policy.isProtectedRoot(home.appendingPathComponent("Library/Caches")))
    }

    @Test func systemFoldersAreProtected() {
        let policy = makePolicy(home: URL(fileURLWithPath: "/Users/tester"))
        #expect(policy.isProtectedRoot(URL(fileURLWithPath: "/System")))
        #expect(policy.isProtectedRoot(URL(fileURLWithPath: "/Applications")))
        #expect(policy.isProtectedRoot(URL(fileURLWithPath: "/Library/Fonts")))
    }

    @Test func downloadsSubfolderIsAllowed() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let policy = makePolicy(home: home)
        #expect(!policy.isProtectedRoot(home.appendingPathComponent("Downloads")))
        #expect(!policy.isProtectedRoot(home.appendingPathComponent("Desktop")))
    }

    @Test func anotherUsersHomeIsAllowedAsRoot() {
        // /Users itself is protected (exact match), but a specific user's home
        // beneath it is a normal, organizable folder.
        let home = URL(fileURLWithPath: "/Users/tester")
        let policy = makePolicy(home: home)
        #expect(!policy.isProtectedRoot(URL(fileURLWithPath: "/Users/someoneelse")))
    }

    @Test func containmentResolvesSymlinks() throws {
        let base = try TestFS.makeTempDirectory()
        let real = try TestFS.makeDirectory("real", in: base)
        let link = base.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let inner = try TestFS.write("f.txt", in: real)

        let policy = makePolicy(home: URL(fileURLWithPath: "/Users/tester"))
        #expect(policy.isContained(inner, in: [link]))
    }
}
