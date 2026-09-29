import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct RawFileStat: Sendable {
    public let size: Int64
    public let modificationDate: Date
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let identity: FileIdentity
}

public enum FileMetadataError: Error {
    case statFailed(path: String, errno: Int32)
}

/// Thin wrapper over POSIX `lstat` (never follows symlinks). Used instead of
/// `URL.resourceValues` for scanning because it's a single syscall per entry
/// and gives us the raw device/inode pair identity checks need.
public enum FileMetadata {
    public static func lstat(_ url: URL) throws -> RawFileStat {
        var st = stat()
        let rc = url.path.withCString { Darwin.lstat($0, &st) }
        guard rc == 0 else {
            throw FileMetadataError.statFailed(path: url.path, errno: errno)
        }
        let isDir = (st.st_mode & S_IFMT) == S_IFDIR
        let isLink = (st.st_mode & S_IFMT) == S_IFLNK
        let seconds = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000
        return RawFileStat(
            size: Int64(st.st_size),
            modificationDate: Date(timeIntervalSince1970: seconds),
            isDirectory: isDir,
            isSymbolicLink: isLink,
            identity: FileIdentity(device: Int32(st.st_dev), inode: UInt64(st.st_ino))
        )
    }

    /// True if the name starts with '.' — matches organize_mac.py's `is_hidden`.
    public static func isDotHidden(_ name: String) -> Bool {
        name.hasPrefix(".")
    }
}
