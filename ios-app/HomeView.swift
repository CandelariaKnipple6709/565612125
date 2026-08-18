import SwiftUI

/// The "new tab" / home screen: a grid of bookmark tiles, Safari/Chrome
/// start-page style. Tapping a tile navigates the current tab to it.
struct HomeView: View {
    let bookmarks: [Bookmark]
    let onOpen: (Bookmark) -> Void

    private let columns = [GridItem(.adaptive(minimum: 90, maximum: 110), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "video.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 28)

                Text("CamSwap")
                    .font(.title2.weight(.semibold))

                if bookmarks.isEmpty {
                    VStack(spacing: 8) {
                        Text("Пока нет закладок")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Откройте сайт и нажмите на звёздочку в адресной строке, чтобы добавить его сюда.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 20)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(bookmarks) { bookmark in
                            Button {
                                onOpen(bookmark)
                            } label: {
                                bookmarkTile(bookmark)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func bookmarkTile(_ bookmark: Bookmark) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 56, height: 56)
                Text(String((bookmark.title.first ?? "?")).uppercased())
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            }
            Text(bookmark.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 90)
        }
    }
}
