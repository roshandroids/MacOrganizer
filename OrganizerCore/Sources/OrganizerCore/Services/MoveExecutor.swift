import Foundation

public enum MoveExecutionError: Error, Sendable {
    case sourceMissing
    case sourceChanged
}

/// Shared move logic for OrganizationService and ArchiveService: re-verify the
/// file against disk immediately before moving (never trust a stale preview),
/// create only the directories that don't already exist, and move atomically
/// with no-clobber collision naming.
public enum MoveExecutor {
    public static func ensureDirectoryExists(_ dir: URL) throws -> [URL] {
        var missing: [URL] = []
        var current = dir
        while !FileManager.default.fileExists(atPath: current.path) {
            missing.append(current)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        for directory in missing.reversed() {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        return missing
    }

    @discardableResult
    public static func verifyAndMove(_ item: FileItem, to destination: URL) throws -> (finalURL: URL, createdDirectories: [URL]) {
        guard FileManager.default.fileExists(atPath: item.path.path) else {
            throw MoveExecutionError.sourceMissing
        }
        let current = try FileMetadata.lstat(item.path)
        guard current.identity == item.identity, current.size == item.size,
              abs(current.modificationDate.timeIntervalSince(item.modificationDate)) < 1 else {
            throw MoveExecutionError.sourceChanged
        }

        let createdDirs = try ensureDirectoryExists(destination.deletingLastPathComponent())
        var finalDestination = destination
        var attempt = 0
        while true {
            do {
                try AtomicMove.moveExclusive(from: item.path, to: finalDestination)
                return (finalDestination, createdDirs)
            } catch AtomicMoveError.destinationExists {
                attempt += 1
                finalDestination = CollisionNaming.numbered(destination, counter: attempt)
            }
        }
    }
}
