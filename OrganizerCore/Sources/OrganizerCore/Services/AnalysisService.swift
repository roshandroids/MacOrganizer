import Foundation

public struct AnalysisOptions: Sendable {
    public let largeFileThresholdBytes: Int64
    public let oldFileThresholdDays: Int
    public let oldInstallerThresholdDays: Int
    public let recentlyModifiedMinutes: Int
    public let keepDirectories: [URL]

    public init(
        largeFileThresholdBytes: Int64, oldFileThresholdDays: Int,
        oldInstallerThresholdDays: Int, recentlyModifiedMinutes: Int, keepDirectories: [URL]
    ) {
        self.largeFileThresholdBytes = largeFileThresholdBytes
        self.oldFileThresholdDays = oldFileThresholdDays
        self.oldInstallerThresholdDays = oldInstallerThresholdDays
        self.recentlyModifiedMinutes = recentlyModifiedMinutes
        self.keepDirectories = keepDirectories
    }
}

/// Builds the read-only declutter report (organize_mac.py's `analyze`).
/// Building a report never writes to disk.
///
/// Two deliberate corrections versus the Python reference:
///  - old-file / old-installer candidates also skip in-progress downloads and
///    files modified within the recency window (Python's `analyze()` didn't
///    apply that check, so a file mid-download could be flagged "old").
///  - duplicate grouping is done on distinct (device, inode) identities, so
///    hard-linked paths are never reported as duplicates of each other.
public actor AnalysisService {
    public static let archiveDirectoryName = "_Archive"

    private let scanner = FileScanner()
    private let duplicateDetector = DuplicateDetectionService()
    private let policy: PathPolicy

    public init(policy: PathPolicy = .system()) {
        self.policy = policy
    }

    public func analyze(
        root: URL, options: AnalysisOptions, clock: Clock,
        onScanProgress: (@Sendable (Int) -> Void)? = nil
    ) async -> ScanReport {
        var report = ScanReport()
        let scanResult = await scanner.scan(root: root, onProgress: onScanProgress)
        report.files = scanResult.files
        report.errors.append(contentsOf: scanResult.errors)

        let now = clock.now()
        let oldCutoff = now.addingTimeInterval(-Double(options.oldFileThresholdDays) * 86400)
        let installerCutoff = now.addingTimeInterval(-Double(options.oldInstallerThresholdDays) * 86400)
        let recentCutoff = now.addingTimeInterval(-Double(options.recentlyModifiedMinutes * 60))
        let archiveRoot = root.appendingPathComponent(Self.archiveDirectoryName)

        var sizes: [String: Int64] = [:]
        for file in report.files {
            let topKey = topLevelComponent(of: file.path, relativeTo: root)
            sizes[topKey, default: 0] += file.size

            if file.size >= options.largeFileThresholdBytes {
                report.largeFiles.append(file)
            }

            if policy.isContained(file.path, in: [archiveRoot]) || policy.isContained(file.path, in: options.keepDirectories) {
                continue
            }
            let ext = file.path.pathExtension.lowercased()
            if SkipRules.inProgressExtensions.contains(ext) || file.modificationDate > recentCutoff {
                continue
            }
            if file.modificationDate < oldCutoff {
                report.oldFiles.append(file)
            }
            if SkipRules.installerCleanupExtensions.contains(ext), file.modificationDate < installerCutoff {
                report.oldInstallers.append(file)
            }
        }
        report.folderSizes = sizes

        var pool: [String: FileItem] = [:]
        for file in report.files { pool[file.path.path] = file }
        for keepDir in options.keepDirectories {
            if keepDir == root || policy.isContained(keepDir, in: [root]) { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: keepDir.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                report.errors.append("--keep-dir is not a folder: \(keepDir.path)")
                continue
            }
            let extra = await scanner.scan(root: keepDir)
            report.errors.append(contentsOf: extra.errors)
            for file in extra.files where pool[file.path.path] == nil {
                pool[file.path.path] = file
            }
        }

        let dupResult = await duplicateDetector.findDuplicates(in: Array(pool.values))
        report.duplicateGroups = dupResult.groups
        report.errors.append(contentsOf: dupResult.errors)

        report.emptyFolders = Self.findEmptyFolders(root: root)

        report.largeFiles.sort { $0.size > $1.size }
        report.oldFiles.sort { $0.size > $1.size }
        report.oldInstallers.sort { $0.size > $1.size }
        report.scannedAt = now
        return report
    }

    private func topLevelComponent(of path: URL, relativeTo root: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard path.path.hasPrefix(rootPath) else { return "(loose files)" }
        let relative = String(path.path.dropFirst(rootPath.count))
        let parts = relative.split(separator: "/")
        return parts.count > 1 ? String(parts[0]) : "(loose files)"
    }

    /// Top-most folders that are empty, or contain only ".DS_Store" / other
    /// empty folders. Hidden, package and junk directories are never descended
    /// into (so their contents can't count toward emptiness of an ancestor).
    public static func findEmptyFolders(root: URL) -> [EmptyFolderCandidate] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []
        ) else { return [] }

        var directories: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values?.isDirectory == true else { continue }
            if FileMetadata.isDotHidden(name) { enumerator.skipDescendants(); continue }
            if SkipRules.skipDirectoryNames.contains(name) { enumerator.skipDescendants(); continue }
            if SkipRules.isPackage(name: name, isDirectory: true) { enumerator.skipDescendants(); continue }
            directories.append(url)
        }

        let deepestFirst = directories.sorted { $0.pathComponents.count > $1.pathComponents.count }
        var emptyPaths: Set<String> = []
        for directory in deepestFirst {
            let children = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            let allEmpty = children.allSatisfy { $0.lastPathComponent == ".DS_Store" || emptyPaths.contains($0.path) }
            if allEmpty { emptyPaths.insert(directory.path) }
        }

        let topmost = emptyPaths.filter { path in
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
            return !emptyPaths.contains(parent)
        }
        return topmost.sorted().map { EmptyFolderCandidate(path: URL(fileURLWithPath: $0)) }
    }
}
