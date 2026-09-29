import Foundation

/// Archives old files into `_Archive/<year>/<category>/`, moved (not trashed) so
/// they're recoverable with plain Undo. Each move is re-verified against disk
/// immediately before executing (see MoveExecutor).
public actor ArchiveService {
    public init() {}

    public func plan(oldFiles: [FileItem], root: URL) -> [PlannedArchiveMove] {
        var reserved: Set<String> = []
        var moves: [PlannedArchiveMove] = []
        for file in oldFiles {
            let year = Calendar.current.component(.year, from: file.modificationDate)
            let category = OrganizationRule.category(
                forFileNamed: file.path.lastPathComponent, extension: file.path.pathExtension
            )
            let targetDir = root
                .appendingPathComponent(AnalysisService.archiveDirectoryName)
                .appendingPathComponent(String(year))
                .appendingPathComponent(category.rawValue)
            var dest = targetDir.appendingPathComponent(file.path.lastPathComponent)
            var counter = 1
            while FileManager.default.fileExists(atPath: dest.path) || reserved.contains(CollisionNaming.foldKey(dest)) {
                dest = CollisionNaming.numbered(targetDir.appendingPathComponent(file.path.lastPathComponent), counter: counter)
                counter += 1
            }
            reserved.insert(CollisionNaming.foldKey(dest))
            moves.append(PlannedArchiveMove(source: file, destination: dest, year: year, category: category))
        }
        return moves
    }

    public func apply(_ moves: [PlannedArchiveMove]) async -> (records: [OperationRecord], errors: [String]) {
        var records: [OperationRecord] = []
        var errors: [String] = []
        for move in moves {
            do {
                let (finalURL, createdDirs) = try MoveExecutor.verifyAndMove(move.source, to: move.destination)
                records.append(OperationRecord(
                    kind: .archiveMove, source: move.source.path, destination: finalURL, trashResultURL: nil,
                    sizeBytes: move.source.size, identity: move.source.identity,
                    sourceModificationDate: move.source.modificationDate, createdDirectories: createdDirs
                ))
            } catch MoveExecutionError.sourceMissing {
                errors.append("Skipped \(move.source.path.lastPathComponent): no longer exists.")
            } catch MoveExecutionError.sourceChanged {
                errors.append("Skipped \(move.source.path.lastPathComponent): changed since preview.")
            } catch {
                errors.append("Archive failed \(move.source.path.path): \(error.localizedDescription)")
            }
        }
        return (records, errors)
    }
}

public struct PlannedArchiveMove: Sendable, Identifiable {
    public let source: FileItem
    public let destination: URL
    public let year: Int
    public let category: FileCategory
    public var id: String { source.path.path }
}
