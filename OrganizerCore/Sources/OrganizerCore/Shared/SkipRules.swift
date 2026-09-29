import Foundation

/// Constants ported verbatim from organize_mac.py's module-level skip tables.
public enum SkipRules {
    /// Folders macOS treats as a single item (bundles) — never look inside.
    public static let packageExtensions: Set<String> = [
        "app", "photoslibrary", "xcodeproj", "xcworkspace", "bundle", "framework",
        "rtfd", "playground", "sparsebundle", "band", "imovielibrary", "fcpbundle",
        "logicx", "pkg", "key", "pages", "numbers",
    ]

    /// Junk folders never descended into.
    public static let skipDirectoryNames: Set<String> = ["node_modules", "__pycache__", "Pods"]

    /// Extensions for downloads still in progress.
    public static let inProgressExtensions: Set<String> = [
        "crdownload", "download", "part", "opdownload", "tmp", "partial",
    ]

    public static let installerCleanupExtensions: Set<String> = ["dmg", "pkg", "iso"]

    /// True if `url` is a directory macOS treats as a single bundle/package.
    public static func isPackage(name: String, isDirectory: Bool) -> Bool {
        guard isDirectory else { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return !ext.isEmpty && packageExtensions.contains(ext)
    }

    /// Duplicate-looking names: "report (1).pdf", "report copy.pdf".
    static let copyNameRegex = try! NSRegularExpression(
        pattern: #"(\s\(\d+\)|\scopy(\s\d+)?)$"#, options: [.caseInsensitive]
    )

    /// True if the filename stem looks like a generated/duplicate copy.
    public static func looksLikeCopyName(stem: String) -> Bool {
        let range = NSRange(stem.startIndex..., in: stem)
        return copyNameRegex.firstMatch(in: stem, options: [], range: range) != nil
    }
}
