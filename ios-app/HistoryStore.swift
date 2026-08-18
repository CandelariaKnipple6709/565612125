import Foundation
import Combine

/// Persists browsing history (title/url/date) to its own JSON file —
/// separate from bookmarks on purpose. clearAll() is what the bottom
/// "clear everything" button calls, alongside wiping WKWebsiteDataStore.
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL
    private let maxEntries = 2000

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("camswap_history.json")
        load()
    }

    func record(title: String, urlString: String) {
        guard !urlString.isEmpty, urlString != "about:blank" else { return }
        let entry = HistoryEntry(title: title.isEmpty ? urlString : title, urlString: urlString)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        persist()
    }

    func remove(atOffsets offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        persist()
    }

    /// Wipes ONLY history — bookmarks are a separate store and are never
    /// touched here.
    func clearAll() {
        entries.removeAll()
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
