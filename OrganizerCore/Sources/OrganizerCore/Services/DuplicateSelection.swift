import Foundation

/// Pure decision logic for which copy in a duplicate group to suggest keeping.
/// Ported from organize_mac.py's `pick_keeper` / `default_keepers`. Contains no
/// I/O — the UI and CleanupService both call through this so the suggested
/// marks are always consistent.
public enum DuplicateSelection {
    /// Suggested single copy to keep when nothing is protected: prefers a
    /// non-"copy"-looking name, then the oldest file, then the shortest path.
    public static func pickKeeper(_ group: [FileItem]) -> FileItem {
        group.min { lhs, rhs in
            let lhsLooksCopy = SkipRules.looksLikeCopyName(stem: lhs.path.deletingPathExtension().lastPathComponent)
            let rhsLooksCopy = SkipRules.looksLikeCopyName(stem: rhs.path.deletingPathExtension().lastPathComponent)
            if lhsLooksCopy != rhsLooksCopy { return !lhsLooksCopy }
            if lhs.modificationDate != rhs.modificationDate { return lhs.modificationDate < rhs.modificationDate }
            return lhs.path.path.count < rhs.path.path.count
        }!
    }

    /// Suggested copies to keep: everything already inside a protected
    /// (--keep-dir) folder, otherwise the single best copy.
    public static func defaultKeepers(_ group: [FileItem], keepDirectories: [URL], policy: PathPolicy) -> Set<URL> {
        let protectedPaths = group.filter { policy.isContained($0.path, in: keepDirectories) }.map(\.path)
        if !protectedPaths.isEmpty { return Set(protectedPaths) }
        return [pickKeeper(group).path]
    }

    /// Every duplicate in `groups` that is NOT among the suggested keepers.
    public static func extras(groups: [DuplicateGroup], keepDirectories: [URL], policy: PathPolicy) -> [FileItem] {
        groups.flatMap { group -> [FileItem] in
            let keep = defaultKeepers(group.items, keepDirectories: keepDirectories, policy: policy)
            return group.items.filter { !keep.contains($0.path) }
        }
    }
}
