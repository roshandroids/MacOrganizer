import Foundation

public struct CleanupStageResult: Sendable {
    public let records: [OperationRecord]
    public let trashed: [TrashedItem]
    public let errors: [String]
}

/// Orchestrates the four cleanup stages (duplicates, old installers, archive,
/// empty folders). Every stage re-verifies its targets against the live
/// filesystem immediately before acting — a stale Preview never gets acted on.
public actor CleanupService {
    private let trashService: TrashService
    private let archiveService = ArchiveService()
    private let policy: PathPolicy

    public init(trashService: TrashService = SystemTrashService(), policy: PathPolicy = .system()) {
        self.trashService = trashService
        self.policy = policy
    }

    /// Trashes the duplicate copies the user chose to remove. Refuses to trash
    /// every copy in a group (at least one keeper must survive), and skips a
    /// copy if the file it was meant to defer to no longer exists — otherwise a
    /// race could delete the last surviving copy of a duplicate set.
    public func trashDuplicates(decisions: [DuplicateDecision], groups: [DuplicateGroup]) async -> CleanupStageResult {
        var candidates: [TrashCandidate] = []
        var errors: [String] = []
        let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })

        for decision in decisions {
            guard let group = groupsByID[decision.groupID] else { continue }
            let keepers = group.items.filter { decision.keepPaths.contains($0.path) }
            guard !keepers.isEmpty else {
                errors.append("Refused to trash every copy of \(group.items.first?.path.lastPathComponent ?? "a file") — at least one copy is always kept.")
                continue
            }
            let keepersStillExist = keepers.contains { FileManager.default.fileExists(atPath: $0.path.path) }
            guard keepersStillExist else {
                errors.append("Skipped duplicate set for \(group.items.first?.path.lastPathComponent ?? "a file"): the copy being kept no longer exists.")
                continue
            }
            for item in group.items where !decision.keepPaths.contains(item.path) {
                candidates.append(TrashCandidate(url: item.path, size: item.size, identity: item.identity, modificationDate: item.modificationDate))
            }
        }
        return await trash(candidates, preErrors: errors)
    }

    public func trashOldInstallers(_ items: [FileItem]) async -> CleanupStageResult {
        await trash(items.map { TrashCandidate(url: $0.path, size: $0.size, identity: $0.identity, modificationDate: $0.modificationDate) })
    }

    /// Trashes empty folders, excluding anything inside a protected (--keep-dir)
    /// folder — organize_mac.py's cleanup ignored keep-dirs for this stage.
    public func trashEmptyFolders(_ candidates: [EmptyFolderCandidate], keepDirectories: [URL]) async -> CleanupStageResult {
        let eligible = candidates.filter { !policy.isContained($0.path, in: keepDirectories) }
        let stats: [TrashCandidate] = eligible.compactMap { candidate in
            guard let stat = try? FileMetadata.lstat(candidate.path) else { return nil }
            return TrashCandidate(url: candidate.path, size: 0, identity: stat.identity, modificationDate: stat.modificationDate)
        }
        return await trash(stats)
    }

    public func archiveOldFiles(_ items: [FileItem], root: URL) async -> CleanupStageResult {
        let plan = await archiveService.plan(oldFiles: items, root: root)
        let result = await archiveService.apply(plan)
        return CleanupStageResult(records: result.records, trashed: [], errors: result.errors)
    }

    // MARK: - Trash helper

    private struct TrashCandidate {
        let url: URL
        let size: Int64
        let identity: FileIdentity
        let modificationDate: Date
    }

    private func trash(_ candidates: [TrashCandidate], preErrors: [String] = []) async -> CleanupStageResult {
        var errors = preErrors
        let stillExisting = candidates.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        guard !stillExisting.isEmpty else {
            return CleanupStageResult(records: [], trashed: [], errors: errors)
        }
        let outcome = await trashService.trash(stillExisting.map(\.url))
        errors.append(contentsOf: outcome.errors)

        let byURL = Dictionary(uniqueKeysWithValues: candidates.map { ($0.url, $0) })
        let records = outcome.trashed.map { trashed -> OperationRecord in
            let info = byURL[trashed.source]
            return OperationRecord(
                kind: .trash, source: trashed.source, destination: nil, trashResultURL: trashed.resultingURL,
                sizeBytes: info?.size ?? 0, identity: info?.identity ?? FileIdentity(device: 0, inode: 0),
                sourceModificationDate: info?.modificationDate ?? Date()
            )
        }
        return CleanupStageResult(records: records, trashed: outcome.trashed, errors: errors)
    }
}
