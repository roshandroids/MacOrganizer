import Foundation

public struct TrashedItem: Sendable {
    public let source: URL
    public let resultingURL: URL?
    public init(source: URL, resultingURL: URL?) {
        self.source = source
        self.resultingURL = resultingURL
    }
}

public struct TrashOutcome: Sendable {
    public let trashed: [TrashedItem]
    public let errors: [String]
}

/// Sends files to the macOS Trash rather than deleting them, so Finder's
/// "Put Back" works. Never calls `FileManager.removeItem` for user data.
/// A protocol so tests can inject a fake instead of touching the real `~/.Trash`.
public protocol TrashService: Sendable {
    func trash(_ urls: [URL]) async -> TrashOutcome
}

public struct SystemTrashService: TrashService {
    public init() {}

    public func trash(_ urls: [URL]) async -> TrashOutcome {
        var trashed: [TrashedItem] = []
        var errors: [String] = []
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else {
                errors.append("Skipped \(url.lastPathComponent): no longer exists.")
                continue
            }
            var resultingURL: NSURL?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                trashed.append(TrashedItem(source: url, resultingURL: resultingURL as URL?))
            } catch {
                errors.append("Couldn't move \(url.lastPathComponent) to Trash: \(error.localizedDescription)")
            }
        }
        return TrashOutcome(trashed: trashed, errors: errors)
    }
}
