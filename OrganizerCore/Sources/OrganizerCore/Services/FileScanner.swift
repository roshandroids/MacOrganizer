import Foundation

public struct ScanResult: Sendable {
    public let files: [FileItem]
    public let errors: [String]
}

/// Recursively walks a folder tree off the main actor so the UI stays responsive
/// on folders with tens of thousands of files. Applies the same skip rules as
/// organize_mac.py's `iter_files`: hidden items, symlinks, package bundles and
/// junk directories are never descended into or returned.
public actor FileScanner {
    public init() {}

    /// Scans `root`. `onProgress` is called periodically with a running file
    /// count; `isCancelled` is polled between directories so a scan of a huge
    /// tree can be abandoned promptly.
    public func scan(
        root: URL,
        onProgress: (@Sendable (Int) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) async -> ScanResult {
        var files: [FileItem] = []
        var errors: [String] = []
        var stack: [URL] = [root]
        var count = 0

        while let current = stack.popLast() {
            if isCancelled?() == true { break }
            let entries: [URL]
            do {
                entries = try FileManager.default.contentsOfDirectory(
                    at: current, includingPropertiesForKeys: nil, options: []
                )
            } catch {
                errors.append("Cannot read folder \(current.path): \(error.localizedDescription)")
                continue
            }

            for entry in entries {
                let name = entry.lastPathComponent
                if FileMetadata.isDotHidden(name) { continue }

                let stat: RawFileStat
                do {
                    stat = try FileMetadata.lstat(entry)
                } catch {
                    errors.append("Cannot stat \(entry.path)")
                    continue
                }
                if stat.isSymbolicLink { continue }

                if stat.isDirectory {
                    if SkipRules.skipDirectoryNames.contains(name) { continue }
                    if SkipRules.isPackage(name: name, isDirectory: true) { continue }
                    stack.append(entry)
                    continue
                }

                if isUndownloadedCloudPlaceholder(entry) { continue }

                files.append(FileItem(
                    path: entry, size: stat.size, modificationDate: stat.modificationDate,
                    identity: stat.identity
                ))
                count += 1
                if count % 250 == 0 { onProgress?(count) }
            }
        }
        onProgress?(count)
        return ScanResult(files: files, errors: errors)
    }

    /// iCloud dataless files have real names on current macOS (no ".name.icloud"
    /// stub) but reading their contents triggers a download. Skip anything not
    /// already fully downloaded so a scan never fetches files from iCloud.
    private nonisolated func isUndownloadedCloudPlaceholder(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
              let status = values.ubiquitousItemDownloadingStatus else {
            return false
        }
        return status != .current
    }
}
