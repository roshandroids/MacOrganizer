import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// The single source of truth for "is this path safe to touch". Every service
/// that moves, archives or trashes files re-checks through this type immediately
/// before acting — the UI disabling a button is never sufficient on its own.
///
/// Injectable so tests can use a sandbox home/protected set instead of the
/// real machine's `/`, `~`, `~/Library` (which would otherwise make every
/// temp-directory test fail validation).
public struct PathPolicy: Sendable {
    public let homeDirectory: URL
    /// Paths that are protected only as an exact match — subfolders beneath
    /// them (e.g. ~/Downloads under ~, or a user's home under /Users) are fine.
    public let protectedExactPaths: Set<URL>
    /// Paths protected as a whole subtree — the path itself and everything
    /// beneath it is off limits.
    public let protectedSubtreeRoots: Set<URL>

    public init(homeDirectory: URL, protectedExactPaths: Set<URL>, protectedSubtreeRoots: Set<URL>) {
        self.homeDirectory = homeDirectory
        self.protectedExactPaths = protectedExactPaths
        self.protectedSubtreeRoots = protectedSubtreeRoots
    }

    /// The policy used by the real app: `/`, the real home and `/Users` are
    /// exact-protected (their subfolders are normal user data); `~/Library`,
    /// `/System`, `/Library`, `/Applications`, `/usr` and `/private` are
    /// protected as whole subtrees.
    public static func system() -> PathPolicy {
        let home = realHomeDirectory()
        return PathPolicy(
            homeDirectory: home,
            protectedExactPaths: [
                URL(fileURLWithPath: "/"),
                home,
                URL(fileURLWithPath: "/Users"),
            ],
            protectedSubtreeRoots: [
                home.appendingPathComponent("Library"),
                URL(fileURLWithPath: "/System"),
                URL(fileURLWithPath: "/Library"),
                URL(fileURLWithPath: "/Applications"),
                URL(fileURLWithPath: "/usr"),
                URL(fileURLWithPath: "/private"),
            ]
        )
    }

    /// The real home directory from the password database, not `NSHomeDirectory()`
    /// / `FileManager.homeDirectoryForCurrentUser` — inside an App Sandbox container
    /// those return the container path, which would silently defeat the `~` check.
    public static func realHomeDirectory() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Resolve symlinks and standardize so `/var` vs `/private/var`, or a
    /// symlinked project folder, compare equal to their real location.
    public static func normalize(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    public func isProtectedRoot(_ url: URL) -> Bool {
        let resolved = Self.normalize(url)
        if protectedExactPaths.contains(where: { Self.normalize($0) == resolved }) {
            return true
        }
        return protectedSubtreeRoots.contains { subtree in
            isEqualOrDescendant(resolved, of: Self.normalize(subtree))
        }
    }

    /// True if `path` is `directory` or lives inside it.
    public func isContained(_ path: URL, in directories: some Sequence<URL>) -> Bool {
        let resolved = Self.normalize(path)
        return directories.contains { isEqualOrDescendant(resolved, of: Self.normalize($0)) }
    }

    private func isEqualOrDescendant(_ path: URL, of directory: URL) -> Bool {
        if path == directory { return true }
        let dirPath = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        return path.path.hasPrefix(dirPath)
    }
}
