import Foundation
import Combine

/// Persists bookmarks to a JSON file in the app's Documents directory —
/// deliberately NOT in UserDefaults/WKWebsiteDataStore, and deliberately
/// never touched by HistoryStore.clearAll() or the website-data wipe in
/// TabManager.clearAllBrowsingData(). Bookmarks are the one thing the
/// "clear everything" button must never delete.
final class BookmarkStore: ObservableObject {
    static let shared = BookmarkStore()

    @Published private(set) var bookmarks: [Bookmark] = []

    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("camswap_bookmarks.json")
        load()
    }

    func add(title: String, urlString: String) {
        // Avoid obvious duplicates (same URL).
        if bookmarks.contains(where: { $0.urlString == urlString }) { return }
        let bookmark = Bookmark(
            title: title.isEmpty ? urlString : title,
            urlString: urlString,
            logoURLString: BookmarkStore.faviconURLString(for: urlString)
        )
        bookmarks.insert(bookmark, at: 0)
        persist()
    }

    /// Builds a Google s2/favicons URL from any site URL string's host, so
    /// every bookmark (whether added via the star button or the "+" add
    /// flow) can render a real logo tile instead of a plain initial.
    static func faviconURLString(for urlString: String) -> String? {
        guard let host = URL(string: urlString)?.host, !host.isEmpty else { return nil }
        return "https://www.google.com/s2/favicons?sz=128&domain=\(host)"
    }

    func remove(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        persist()
    }

    func remove(atOffsets offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        persist()
    }

    func isBookmarked(urlString: String) -> Bool {
        bookmarks.contains { $0.urlString == urlString }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = decoded
            backfillMissingLogos()
        }
    }

    /// Older bookmarks saved before logoURLString existed decode with a
    /// nil logo — fill those in from the host so the home-screen grid
    /// looks visually consistent without requiring the user to re-add
    /// anything.
    private func backfillMissingLogos() {
        var changed = false
        for i in bookmarks.indices where bookmarks[i].logoURLString == nil {
            if let logo = BookmarkStore.faviconURLString(for: bookmarks[i].urlString) {
                bookmarks[i].logoURLString = logo
                changed = true
            }
        }
        if changed { persist() }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
