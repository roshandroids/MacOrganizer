import Foundation

public struct UndoResult: Sendable {
    public let outcomes: [UndoOutcome]
    public let restoredCount: Int
    /// Trashed items in this run aren't reversed here — Finder's Put Back is
    /// the recovery path for those. Reported so the UI can say so.
    public let unreversedTrashedCount: Int
}

/// Reverses a logged run, safely.
///
/// Deliberately stricter than organize_mac.py's `undo`, which silently renames
/// around an occupied source path. Here, an occupied source is reported as a
/// conflict and skipped — restoring must never risk overwriting a file that
/// appeared after the original move. Every restore also re-verifies the file
/// at the destination still has the identity (device+inode) that was moved
/// there, so a file a user has since edited-in-place or replaced is not
/// silently relocated.
public actor UndoService {
    public init() {}

    public func undo(run: OperationRun) async -> UndoResult {
        var outcomes: [UndoOutcome] = []
        var createdDirectoriesFromRestored: [URL] = []

        let moveRecords = run.records.filter { $0.kind != .trash && $0.destination != nil }
        for record in moveRecords.reversed() {
            guard let destination = record.destination else { continue }

            guard FileManager.default.fileExists(atPath: destination.path) else {
                outcomes.append(.skippedMissingDestination(record))
                continue
            }
            guard let currentStat = try? FileMetadata.lstat(destination), currentStat.identity == record.identity else {
                outcomes.append(.skippedChanged(record))
                continue
            }
            if FileManager.default.fileExists(atPath: record.source.path) {
                outcomes.append(.skippedSourceOccupied(record, occupant: record.source))
                continue
            }

            do {
                _ = try MoveExecutor.ensureDirectoryExists(record.source.deletingLastPathComponent())
                try AtomicMove.moveExclusive(from: destination, to: record.source)
                outcomes.append(.restored(record))
                createdDirectoriesFromRestored.append(contentsOf: record.createdDirectories)
            } catch {
                outcomes.append(.failed(record, describeMoveError(error)))
            }
        }

        Self.removeIfNowEmpty(createdDirectoriesFromRestored)

        let trashedCount = run.records.filter { $0.kind == .trash }.count
        return UndoResult(
            outcomes: outcomes,
            restoredCount: outcomes.filter(\.isSuccess).count,
            unreversedTrashedCount: trashedCount
        )
    }

    private func describeMoveError(_ error: Error) -> String {
        if let atomicError = error as? AtomicMoveError {
            switch atomicError {
            case .destinationExists: return "A file already exists at the restore location."
            case .crossVolume: return "Source and destination are on different volumes."
            case .underlying(_, let message): return message
            }
        }
        return error.localizedDescription
    }

    /// Removes only the directories this run created (per-record, recorded at
    /// move time) and only if they're empty now — never a folder that existed
    /// before the run, and never one a user has since put something into.
    private static func removeIfNowEmpty(_ directories: [URL]) {
        let uniquePaths = Set(directories.map(\.path))
        let deepestFirst = uniquePaths.sorted { $0.split(separator: "/").count > $1.split(separator: "/").count }
        for path in deepestFirst {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path), contents.isEmpty else { continue }
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
