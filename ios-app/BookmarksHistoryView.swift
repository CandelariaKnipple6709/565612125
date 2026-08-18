import SwiftUI

/// Segmented Bookmarks / History browser, reachable from the bottom
/// toolbar's book icon. Deleting a bookmark here only removes it from
/// BookmarkStore; deleting history only removes it from HistoryStore —
/// the two never interact, matching the "bookmarking shouldn't affect
/// history/data" requirement.
struct BookmarksHistoryView: View {
    let onOpen: (String) -> Void

    @ObservedObject private var bookmarkStore = BookmarkStore.shared
    @ObservedObject private var historyStore = HistoryStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var segment = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $segment) {
                    Text("Закладки").tag(0)
                    Text("История").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(12)

                if segment == 0 {
                    bookmarksList
                } else {
                    historyList
                }
            }
            .navigationTitle(segment == 0 ? "Закладки" : "История")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private var bookmarksList: some View {
        Group {
            if bookmarkStore.bookmarks.isEmpty {
                emptyState("Нет закладок", systemImage: "star")
            } else {
                List {
                    ForEach(bookmarkStore.bookmarks) { bookmark in
                        Button {
                            onOpen(bookmark.urlString)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bookmark.title).font(.subheadline).foregroundStyle(.primary)
                                Text(bookmark.urlString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .onDelete { bookmarkStore.remove(atOffsets: $0) }
                }
                .listStyle(.plain)
            }
        }
    }

    private var historyList: some View {
        Group {
            if historyStore.entries.isEmpty {
                emptyState("История пуста", systemImage: "clock")
            } else {
                List {
                    ForEach(historyStore.entries) { entry in
                        Button {
                            onOpen(entry.urlString)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title).font(.subheadline).foregroundStyle(.primary)
                                Text(entry.urlString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .onDelete { historyStore.remove(atOffsets: $0) }
                }
                .listStyle(.plain)
            }
        }
    }

    private func emptyState(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
