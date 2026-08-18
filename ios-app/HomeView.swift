import SwiftUI

/// The "new tab" / home screen: a grid of bookmark tiles, Safari/Chrome
/// start-page style. Tapping a tile navigates the current tab to it.
/// Includes a "+" tile that opens AddSiteSheet to add a new site by URL.
struct HomeView: View {
    let bookmarks: [Bookmark]
    let onOpen: (Bookmark) -> Void

    @State private var showAddSite = false

    private let columns = [GridItem(.adaptive(minimum: 90, maximum: 110), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HomeIcon.image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .padding(.top, 24)

                Text("CamSwap")
                    .font(.title2.weight(.semibold))

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(bookmarks) { bookmark in
                        Button {
                            onOpen(bookmark)
                        } label: {
                            bookmarkTile(bookmark)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        showAddSite = true
                    } label: {
                        addTile
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                if bookmarks.isEmpty {
                    VStack(spacing: 8) {
                        Text("Пока нет закладок")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Откройте сайт и нажмите на звёздочку в адресной строке, или нажмите «+», чтобы добавить его сюда.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showAddSite) {
            AddSiteSheet { name, urlString in
                BookmarkStore.shared.add(title: name, urlString: urlString)
            }
        }
    }

    private func bookmarkTile(_ bookmark: Bookmark) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 56, height: 56)

                if let logoURLString = bookmark.logoURLString, let logoURL = URL(string: logoURLString) {
                    AsyncImage(url: logoURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit().frame(width: 32, height: 32)
                        default:
                            Image(systemName: "globe")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                } else {
                    Image(systemName: "globe")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text(bookmark.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 90)
        }
    }

    private var addTile: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .frame(width: 56, height: 56)
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            Text("Добавить")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90)
        }
    }
}
