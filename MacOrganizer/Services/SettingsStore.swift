import Foundation
import Observation
import OrganizerCore

/// Persists AppSettings to UserDefaults and manages the security-scoped
/// bookmarks that back sandboxed access to any folder the user picked
/// (custom organize root, keep-dirs, or a well-known folder whose special
/// sandbox entitlement didn't resolve — see `resolvedWellKnownFolder`).
@MainActor
@Observable
final class SettingsStore {
    private(set) var settings: AppSettings
    private(set) var resolvedKeepDirectories: [URL] = []
    private(set) var resolvedWellKnownFolders: [String: URL] = [:]

    private var keepDirectoryTokens: [BookmarkAccess.AccessToken] = []
    private var defaultFolderToken: BookmarkAccess.AccessToken?
    private var wellKnownFolderTokens: [String: BookmarkAccess.AccessToken] = [:]
    private static let defaultsKey = "com.roshanshrestha.macorganizer.settings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? Self.decoder.decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
        resolveKeepDirectories()
        resolveDefaultFolder()
        resolveWellKnownFolders()
    }

    /// True once the user has granted bookmark-based access to a well-known
    /// folder (Desktop/Documents/Downloads/Applications) — used as a fallback
    /// when its special sandbox entitlement doesn't resolve to the real path.
    func hasBookmarkAccess(to folderID: String) -> Bool {
        resolvedWellKnownFolders[folderID] != nil
    }

    func grantWellKnownFolderAccess(_ url: URL, folderID: String) {
        guard let bookmark = try? BookmarkAccess.makeBookmark(for: url) else { return }
        settings.wellKnownFolderBookmarks[folderID] = bookmark
        resolveWellKnownFolders()
        persist()
    }

    private func resolveWellKnownFolders() {
        var tokens: [String: BookmarkAccess.AccessToken] = [:]
        var resolved: [String: URL] = [:]
        for (id, bookmark) in settings.wellKnownFolderBookmarks {
            guard let token = BookmarkAccess.resolveAndAccess(bookmark) else { continue }
            tokens[id] = token
            resolved[id] = token.url
        }
        wellKnownFolderTokens = tokens
        resolvedWellKnownFolders = resolved
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        persist()
    }

    func setWorkingFolder(_ url: URL) {
        settings.defaultFolder = url
        if let bookmark = try? BookmarkAccess.makeBookmark(for: url) {
            settings.defaultFolderBookmark = bookmark
        }
        resolveDefaultFolder()
        persist()
    }

    func addKeepDirectory(_ url: URL) {
        guard let bookmark = try? BookmarkAccess.makeBookmark(for: url) else { return }
        settings.protectedDirectoryBookmarks.append(bookmark)
        resolveKeepDirectories()
        persist()
    }

    func removeKeepDirectories(at offsets: IndexSet) {
        settings.protectedDirectoryBookmarks.remove(atOffsets: offsets)
        resolveKeepDirectories()
        persist()
    }

    private func resolveKeepDirectories() {
        keepDirectoryTokens = settings.protectedDirectoryBookmarks.compactMap { BookmarkAccess.resolveAndAccess($0) }
        resolvedKeepDirectories = keepDirectoryTokens.map(\.url)
    }

    private func resolveDefaultFolder() {
        guard let bookmark = settings.defaultFolderBookmark,
              let token = BookmarkAccess.resolveAndAccess(bookmark) else {
            defaultFolderToken = nil
            return
        }
        defaultFolderToken = token
        settings.defaultFolder = token.url
    }

    private func persist() {
        guard let data = try? Self.encoder.encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
