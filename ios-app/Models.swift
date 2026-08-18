import Foundation

/// A saved bookmark. Bookmarks live in their own store (BookmarkStore) and
/// are never touched by the "clear everything" button — that only wipes
/// cookies/site data and the History list.
struct Bookmark: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var urlString: String
    var dateAdded: Date = Date()
    /// Favicon/logo URL (Google's s2/favicons service, keyed off the
    /// bookmark's host), used to render a real logo instead of just an
    /// initial letter on the home-screen grid. Optional with no explicit
    /// default value is fine here since every existing decode path already
    /// tolerates a missing key via Codable's synthesized init(from:) —
    /// but to be extra safe for bookmarks saved by an older build without
    /// this field, decoding still succeeds and this is simply nil, and
    /// BookmarkStore backfills it on load.
    var logoURLString: String?
}

/// One visited-page record. Purely local, used only to power the History
/// tab and to know what "clear history" should wipe.
struct HistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var urlString: String
    var date: Date = Date()
}
