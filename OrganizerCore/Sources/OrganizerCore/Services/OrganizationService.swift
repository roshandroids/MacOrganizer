import Foundation

public struct PlannedMove: Sendable, Identifiable {
    public let source: FileItem
    public let category: FileCategory
    public let destination: URL
    public var id: String { source.path.path }
}

public struct OrganizePlan: Sendable {
    public let moves: [PlannedMove]
    public let skippedCount: Int
}

/// Plans and executes moving top-level files in a folder into type folders.
/// Directories (including .app-style bundles) are never touched — only
/// `is_file` top-level entries are considered, exactly like organize_mac.py's
/// `plan_moves`.
public actor OrganizationService {
    public init() {}

    public func plan(
        root: URL, byDate: Bool, dateFormat: DateFolderFormat,
        recentlyModifiedMinutes: Int, clock: Clock
    ) throws -> OrganizePlan {
        let entries = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])
            .sorted { $0.path < $1.path }

        var moves: [PlannedMove] = []
        var reserved: Set<String> = []
        var skipped = 0
        let cutoff = clock.now().addingTimeInterval(-Double(recentlyModifiedMinutes * 60))

        for entry in entries {
            let name = entry.lastPathComponent
            if FileMetadata.isDotHidden(name) { continue }
            guard let stat = try? FileMetadata.lstat(entry) else { continue }
            if stat.isDirectory || stat.isSymbolicLink { continue }

            let ext = entry.pathExtension.lowercased()
            if SkipRules.inProgressExtensions.contains(ext) || stat.modificationDate > cutoff {
                skipped += 1
                continue
            }

            let category = OrganizationRule.category(forFileNamed: name, extension: ext)
            var targetDir = root.appendingPathComponent(category.rawValue)
            if byDate {
                targetDir = targetDir.appendingPathComponent(
                    Self.dateFolderComponent(stat.modificationDate, format: dateFormat)
                )
            }
            let dest = uniqueDestination(targetDir.appendingPathComponent(name), reserved: &reserved)
            moves.append(PlannedMove(
                source: FileItem(path: entry, size: stat.size, modificationDate: stat.modificationDate, identity: stat.identity),
                category: category,
                destination: dest
            ))
        }
        return OrganizePlan(moves: moves, skippedCount: skipped)
    }

    /// Executes a previously-previewed plan. Every move is re-verified against
    /// the live filesystem immediately beforehand — a stale preview (file
    /// deleted, edited, or already moved since Preview) is skipped and reported,
    /// never blindly applied.
    public func apply(moves: [PlannedMove]) async -> (records: [OperationRecord], errors: [String]) {
        var records: [OperationRecord] = []
        var errors: [String] = []

        for move in moves {
            do {
                let (finalURL, createdDirs) = try MoveExecutor.verifyAndMove(move.source, to: move.destination)
                records.append(OperationRecord(
                    kind: .organizeMove, source: move.source.path, destination: finalURL,
                    trashResultURL: nil, sizeBytes: move.source.size, identity: move.source.identity,
                    sourceModificationDate: move.source.modificationDate, createdDirectories: createdDirs
                ))
            } catch MoveExecutionError.sourceMissing {
                errors.append("Skipped \(move.source.path.lastPathComponent): no longer exists.")
            } catch MoveExecutionError.sourceChanged {
                errors.append("Skipped \(move.source.path.lastPathComponent): changed since preview.")
            } catch {
                errors.append("Move failed \(move.source.path.path): \(error.localizedDescription)")
            }
        }
        return (records, errors)
    }

    /// Returns a destination path that neither exists on disk nor is already
    /// reserved by an earlier move in this same plan (case/normalization folded
    /// so "Report.pdf" and "report.pdf" don't collide on APFS).
    private func uniqueDestination(_ dest: URL, reserved: inout Set<String>) -> URL {
        var candidate = dest
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path)
                || reserved.contains(CollisionNaming.foldKey(candidate)) {
            candidate = CollisionNaming.numbered(dest, counter: counter)
            counter += 1
        }
        reserved.insert(CollisionNaming.foldKey(candidate))
        return candidate
    }

    static func dateFolderComponent(_ date: Date, format: DateFolderFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format.rawValue
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
