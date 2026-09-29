import Foundation
import CryptoKit

public struct DuplicateScanResult: Sendable {
    public let groups: [DuplicateGroup]
    public let errors: [String]
}

/// Finds byte-identical files using a staged, cheap-to-expensive pipeline:
/// size bucket -> distinct (device, inode) -> partial hash -> full SHA-256.
/// Hard-linked paths (same device+inode) are the same file on disk, not
/// duplicates, and are collapsed before any hashing happens.
public actor DuplicateDetectionService {
    private let chunkBytes = 1024 * 1024
    private let partialHashBytes = 64 * 1024

    public init() {}

    public func findDuplicates(
        in files: [FileItem],
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> DuplicateScanResult {
        var errors: [String] = []
        var bySize: [Int64: [FileItem]] = [:]
        for file in files where file.size > 0 {
            bySize[file.size, default: []].append(file)
        }

        let candidateSets = bySize.values.filter { $0.count > 1 }
        var hashedCount = 0
        let totalCandidates = candidateSets.reduce(0) { $0 + $1.count }

        var groups: [DuplicateGroup] = []
        for sameSize in candidateSets {
            var seenIdentities: Set<FileIdentity> = []
            var uniqueFiles: [FileItem] = []
            for file in sameSize where seenIdentities.insert(file.identity).inserted {
                uniqueFiles.append(file)
            }
            guard uniqueFiles.count > 1 else { continue }

            var byPartialHash: [String: [FileItem]] = [:]
            for file in uniqueFiles {
                do {
                    let digest = try hash(url: file.path, maxBytes: partialHashBytes)
                    byPartialHash[digest, default: []].append(file)
                } catch {
                    errors.append("Cannot hash \(file.path.path): \(error.localizedDescription)")
                }
                hashedCount += 1
                onProgress?(hashedCount, totalCandidates)
            }

            for candidates in byPartialHash.values where candidates.count > 1 {
                var byFullHash: [String: [FileItem]] = [:]
                for file in candidates {
                    do {
                        let digest = try hash(url: file.path, maxBytes: nil)
                        byFullHash[digest, default: []].append(file)
                    } catch {
                        errors.append("Cannot hash \(file.path.path): \(error.localizedDescription)")
                    }
                }
                for (digest, group) in byFullHash where group.count > 1 {
                    groups.append(DuplicateGroup(hash: digest, items: group))
                }
            }
        }
        return DuplicateScanResult(groups: groups, errors: errors)
    }

    private func hash(url: URL, maxBytes: Int?) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var totalRead = 0
        while true {
            let toRead = maxBytes.map { min(chunkBytes, max(0, $0 - totalRead)) } ?? chunkBytes
            if toRead == 0 { break }
            guard let chunk = try handle.read(upToCount: toRead), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            totalRead += chunk.count
            if let maxBytes, totalRead >= maxBytes { break }
        }
        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
