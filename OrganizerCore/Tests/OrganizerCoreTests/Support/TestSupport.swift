import Foundation
@testable import OrganizerCore

/// Isolated temp directory per test. Never touches the real home directory.
enum TestFS {
    static func makeTempDirectory(_ label: String = #function) throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MacOrganizerTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.resolvingSymlinksInPath()
    }

    @discardableResult
    static func write(_ name: String, in dir: URL, contents: String = "data", modified: Date? = nil) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    @discardableResult
    static func writeBytes(_ name: String, in dir: URL, byteCount: Int, modified: Date? = nil) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(repeating: 0x41, count: byteCount)
        try data.write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    static func makeDirectory(_ name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func daysAgo(_ days: Int) -> Date {
        Date().addingTimeInterval(-Double(days) * 86400)
    }

    static func minutesAgo(_ minutes: Int) -> Date {
        Date().addingTimeInterval(-Double(minutes) * 60)
    }

    static func item(at url: URL) throws -> FileItem {
        let stat = try FileMetadata.lstat(url)
        return FileItem(path: url, size: stat.size, modificationDate: stat.modificationDate, identity: stat.identity)
    }
}

/// Trash double that moves files into a temp "trashcan" instead of the real
/// `~/.Trash`, so tests never touch the user's actual Trash.
actor FakeTrashService: TrashService {
    let trashDirectory: URL
    private(set) var calls: [[URL]] = []

    init(trashDirectory: URL) {
        self.trashDirectory = trashDirectory
    }

    func trash(_ urls: [URL]) async -> TrashOutcome {
        calls.append(urls)
        var trashed: [TrashedItem] = []
        var errors: [String] = []
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else {
                errors.append("missing \(url.path)")
                continue
            }
            let dest = trashDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            do {
                try? FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: url, to: dest)
                trashed.append(TrashedItem(source: url, resultingURL: dest))
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        return TrashOutcome(trashed: trashed, errors: errors)
    }
}
