import Foundation

/// Wraps App Sandbox security-scoped bookmarks: create one when the user picks
/// a folder via NSOpenPanel, resolve it on later launches, and keep
/// `startAccessingSecurityScopedResource` balanced with `stop`.
///
/// `~/Downloads` doesn't need any of this — the app's
/// `com.apple.security.files.downloads.read-write` entitlement grants access
/// without a bookmark. This is only needed for folders the user explicitly
/// picked (a custom Organize root, or a --keep-dir).
enum BookmarkAccess {
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves a bookmark and starts security-scoped access. Call `stop` on
    /// the returned URL when done (an `AccessToken` does this for you on deinit).
    static func resolveAndAccess(_ bookmark: Data) -> AccessToken? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark, options: .withSecurityScope,
            relativeTo: nil, bookmarkDataIsStale: &isStale
        ) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        return AccessToken(url: url, isStale: isStale)
    }

    /// Holds a security-scoped resource open. Stops access automatically when
    /// deallocated — keep a strong reference for as long as you need the URL.
    final class AccessToken {
        let url: URL
        let isStale: Bool
        init(url: URL, isStale: Bool) {
            self.url = url
            self.isStale = isStale
        }
        deinit { url.stopAccessingSecurityScopedResource() }
    }
}
