import Foundation

/// Deterministic collision naming: "photo.jpg" -> "photo (1).jpg" -> "photo (2).jpg".
/// Never overwrites; the destination folder can hold both the original and the
/// newly organized/archived copy under distinct names.
public enum CollisionNaming {
    public static func numbered(_ url: URL, counter: Int) -> URL {
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let name = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
        return url.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// Case- and normalization-folded key so "Report.pdf" and "report.pdf" are
    /// recognized as the same reserved name on case-insensitive APFS.
    public static func foldKey(_ url: URL) -> String {
        url.path.precomposedStringWithCanonicalMapping.lowercased()
    }
}
