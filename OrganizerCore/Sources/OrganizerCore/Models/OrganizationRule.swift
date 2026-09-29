import Foundation

/// A type-based destination folder. Preserves the categories from the Python
/// reference implementation (organize_mac.py CATEGORIES) plus Screenshots/Other.
public enum FileCategory: String, Sendable, CaseIterable, Codable, Identifiable {
    case images = "Images"
    case videos = "Videos"
    case audio = "Audio"
    case documents = "Documents"
    case spreadsheets = "Spreadsheets"
    case presentations = "Presentations"
    case archives = "Archives"
    case installers = "Installers"
    case code = "Code"
    case fonts = "Fonts"
    case screenshots = "Screenshots"
    case other = "Other"

    public var id: String { rawValue }

    /// SF Symbol for this category, used across Overview/Report/Organize UI.
    public var symbolName: String {
        switch self {
        case .images: return "photo"
        case .videos: return "film"
        case .audio: return "waveform"
        case .documents: return "doc.text"
        case .spreadsheets: return "tablecells"
        case .presentations: return "rectangle.on.rectangle"
        case .archives: return "archivebox"
        case .installers: return "shippingbox"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .fonts: return "textformat"
        case .screenshots: return "camera.viewfinder"
        case .other: return "questionmark.folder"
        }
    }
}

/// Extension -> category classification, ported verbatim from the Python
/// CATEGORIES table so existing user behavior is unchanged.
public enum OrganizationRule {
    public static let categoryExtensions: [FileCategory: Set<String>] = [
        .images: ["jpg", "jpeg", "png", "gif", "bmp", "webp", "svg", "heic", "tiff", "ico", "raw", "psd", "sketch", "fig"],
        .videos: ["mp4", "mkv", "mov", "avi", "wmv", "flv", "webm", "m4v"],
        .audio: ["mp3", "wav", "flac", "aac", "ogg", "m4a", "wma", "aiff"],
        .documents: ["pdf", "doc", "docx", "txt", "rtf", "odt", "md", "epub", "pages"],
        .spreadsheets: ["xls", "xlsx", "csv", "ods", "tsv", "numbers"],
        .presentations: ["ppt", "pptx", "key", "odp"],
        .archives: ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz"],
        .installers: ["dmg", "pkg", "iso", "exe", "msi", "deb", "rpm", "apk", "ipa"],
        .code: ["py", "js", "ts", "dart", "java", "kt", "swift", "c", "cpp", "h",
                "cs", "go", "rs", "rb", "php", "html", "css", "json", "yaml", "yml",
                "xml", "sh", "sql", "ipynb"],
        .fonts: ["ttf", "otf", "woff", "woff2"],
    ]

    static let extensionToCategory: [String: FileCategory] = {
        var map: [String: FileCategory] = [:]
        for (category, exts) in categoryExtensions {
            for ext in exts { map[ext] = category }
        }
        return map
    }()

    /// macOS screenshot / recording names, e.g. "Screenshot 2026-09-29 at 10.15.22 AM.png".
    static let screenshotNamePrefixes = ["Screenshot", "Screen Shot", "Screen Recording", "CleanShot"]

    static let screenshotEligibleExtensions: Set<String> =
        (categoryExtensions[.images] ?? []).union(categoryExtensions[.videos] ?? [])

    /// Category folder name a file should be organized into. Screenshots are
    /// detected by filename first (only for image/video extensions), then by extension.
    public static func category(forFileNamed name: String, extension ext: String) -> FileCategory {
        let lowerExt = ext.lowercased()
        if screenshotEligibleExtensions.contains(lowerExt), hasScreenshotPrefix(name) {
            return .screenshots
        }
        return extensionToCategory[lowerExt] ?? .other
    }

    public static let allCategoryDirectoryNames: Set<String> = Set(FileCategory.allCases.map(\.rawValue))

    /// True if `name` starts with a screenshot prefix followed by a word boundary
    /// (mirrors Python's `^(Screenshot|Screen Shot|...)\b` case-insensitively).
    static func hasScreenshotPrefix(_ name: String) -> Bool {
        let lower = name.lowercased()
        for prefix in screenshotNamePrefixes {
            let lowerPrefix = prefix.lowercased()
            guard lower.hasPrefix(lowerPrefix) else { continue }
            let nextIndex = lower.index(lower.startIndex, offsetBy: lowerPrefix.count)
            if nextIndex == lower.endIndex { return true }
            let nextChar = lower[nextIndex]
            if !(nextChar.isLetter || nextChar.isNumber || nextChar == "_") { return true }
        }
        return false
    }
}
