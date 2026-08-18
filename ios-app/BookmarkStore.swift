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
        let bookmark = Bookmark(title: title.isEmpty ? urlString : title, urlString: urlString)
        bookmarks.insert(bookmark, at: 0)
        persist()
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
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
