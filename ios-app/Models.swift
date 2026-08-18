import Foundation

/// A saved bookmark. Bookmarks live in their own store (BookmarkStore) and
/// are never touched by the "clear everything" button — that only wipes
/// cookies/site data and the History list.
struct Bookmark: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var urlString: String
    var dateAdded: Date = Date()
}

/// One visited-page record. Purely local, used only to power the History
/// tab and to know what "clear history" should wipe.
struct HistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var urlString: String
    var date: Date = Date()
}
