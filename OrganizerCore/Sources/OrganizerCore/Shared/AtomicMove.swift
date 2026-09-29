import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum AtomicMoveError: Error, Sendable {
    /// Destination already exists (`renamex_np` with RENAME_EXCL raced someone else,
    /// or our own collision check was stale). Caller should pick the next candidate name.
    case destinationExists
    /// Source and destination are on different volumes. `rename` cannot do this
    /// atomically — a copy+delete would amount to a silent delete on failure
    /// partway through, so we refuse rather than fake it.
    case crossVolume
    case underlying(errno: Int32, message: String)
}

/// Atomic, no-clobber file move. Closes the check-then-move race: `renamex_np`
/// with `RENAME_EXCL` fails atomically if the destination appears between our
/// preview and the actual move, instead of silently overwriting it.
public enum AtomicMove {
    public static func moveExclusive(from source: URL, to destination: URL) throws {
        let rc = source.path.withCString { srcPath in
            destination.path.withCString { dstPath in
                renamex_np(srcPath, dstPath, UInt32(RENAME_EXCL))
            }
        }
        guard rc != 0 else { return }
        switch errno {
        case EEXIST:
            throw AtomicMoveError.destinationExists
        case EXDEV:
            throw AtomicMoveError.crossVolume
        default:
            throw AtomicMoveError.underlying(errno: errno, message: String(cString: strerror(errno)))
        }
    }

    /// True if `a` and `b` live on the same volume (same st_dev), i.e. a rename
    /// between them can be atomic.
    public static func sameVolume(_ a: FileIdentity, _ b: FileIdentity) -> Bool {
        a.device == b.device
    }
}
