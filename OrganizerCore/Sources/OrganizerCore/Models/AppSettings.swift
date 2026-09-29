import Foundation

public enum CollisionStrategy: String, Codable, Sendable, CaseIterable, Identifiable {
    /// "photo.jpg" -> "photo (1).jpg", "photo (2).jpg", ... (matches organize_mac.py)
    case numberedParentheses
    public var id: String { rawValue }
}

public enum DateFolderFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    case yearMonth = "yyyy-MM"       // Images/2026-09/
    case yearOnly = "yyyy"           // Images/2026/
    public var id: String { rawValue }
}

public enum ThemeMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case system, light, dark
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// User-configurable behavior. Persisted via UserDefaults (see SettingsStore in the app target).
/// Thresholds and folders only ever narrow what cleanup touches; safety rules
/// (protected paths, skip rules) are enforced in the service layer and are not
/// exposed as settings that could weaken them.
public struct AppSettings: Codable, Sendable, Equatable {
    public var defaultFolder: URL
    public var organizeByDate: Bool
    public var dateFolderFormat: DateFolderFormat
    public var collisionStrategy: CollisionStrategy
    public var recentlyModifiedMinutes: Int
    public var largeFileThresholdMB: Int
    public var oldFileThresholdDays: Int
    public var oldInstallerThresholdDays: Int
    public var protectedDirectoryBookmarks: [Data]
    /// Security-scoped bookmark for the last folder picked via the open panel
    /// (needed for App Sandbox access outside the Downloads entitlement).
    public var defaultFolderBookmark: Data?
    /// Security-scoped bookmarks for the Overview's well-known folders
    /// (Desktop/Documents/Downloads/Applications), keyed by a stable id
    /// ("desktop", "documents", "downloads", "applications"). Used as a
    /// fallback whenever the matching sandbox entitlement doesn't resolve to
    /// the real folder (e.g. local ad-hoc signing) — granted once via an open
    /// panel and remembered here.
    public var wellKnownFolderBookmarks: [String: Data]
    public var soundEffectsEnabled: Bool
    /// Named system sound played on a successful organize/cleanup completion.
    public var notificationSoundName: String
    public var themeMode: ThemeMode
    /// 0 = fully solid panels, 1 = maximum Liquid Glass translucency. Drives
    /// every glass panel and button in the app (see GlassStyle in the app target).
    public var glassIntensity: Double

    public static let `default` = AppSettings(
        defaultFolder: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads"),
        organizeByDate: false,
        dateFolderFormat: .yearMonth,
        collisionStrategy: .numberedParentheses,
        recentlyModifiedMinutes: 10,
        largeFileThresholdMB: 100,
        oldFileThresholdDays: 180,
        oldInstallerThresholdDays: 14,
        protectedDirectoryBookmarks: [],
        defaultFolderBookmark: nil,
        wellKnownFolderBookmarks: [:],
        soundEffectsEnabled: true,
        notificationSoundName: "Glass",
        themeMode: .system,
        glassIntensity: 0.7
    )

    public init(
        defaultFolder: URL, organizeByDate: Bool, dateFolderFormat: DateFolderFormat,
        collisionStrategy: CollisionStrategy, recentlyModifiedMinutes: Int,
        largeFileThresholdMB: Int, oldFileThresholdDays: Int, oldInstallerThresholdDays: Int,
        protectedDirectoryBookmarks: [Data], defaultFolderBookmark: Data? = nil,
        wellKnownFolderBookmarks: [String: Data] = [:], soundEffectsEnabled: Bool = true,
        notificationSoundName: String = "Glass", themeMode: ThemeMode = .system,
        glassIntensity: Double = 0.7
    ) {
        self.defaultFolder = defaultFolder
        self.organizeByDate = organizeByDate
        self.dateFolderFormat = dateFolderFormat
        self.collisionStrategy = collisionStrategy
        self.recentlyModifiedMinutes = recentlyModifiedMinutes
        self.largeFileThresholdMB = largeFileThresholdMB
        self.oldFileThresholdDays = oldFileThresholdDays
        self.oldInstallerThresholdDays = oldInstallerThresholdDays
        self.protectedDirectoryBookmarks = protectedDirectoryBookmarks
        self.defaultFolderBookmark = defaultFolderBookmark
        self.wellKnownFolderBookmarks = wellKnownFolderBookmarks
        self.soundEffectsEnabled = soundEffectsEnabled
        self.notificationSoundName = notificationSoundName
        self.themeMode = themeMode
        self.glassIntensity = glassIntensity
    }

    public var largeFileThresholdBytes: Int64 { Int64(largeFileThresholdMB) * 1024 * 1024 }
}
