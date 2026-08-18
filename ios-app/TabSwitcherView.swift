import SwiftUI

/// Grid of open tabs (snapshot thumbnail + title/url + close button),
/// styled after the standard Safari/Chrome tab switcher.
struct TabSwitcherView: View {
    let tabs: [BrowserTab]
    let activeTabID: UUID?
    let onSelect: (BrowserTab) -> Void
    let onClose: (BrowserTab) -> Void
    let onNewTab: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14)]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(tabs) { tab in
                        tabCard(tab)
                    }
                    Button(action: onNewTab) {
                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.title)
                            Text("Новая вкладка")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, minHeight: 150)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(14)
            }
            .navigationTitle("Вкладки (\(tabs.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func tabCard(_ tab: BrowserTab) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = tab.snapshot {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.tertiarySystemBackground)
                            .overlay(
                                Image(systemName: tab.isHome ? "house" : "globe")
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                            )
                    }
                }
                .frame(height: 130)
                .clipped()

                Button {
                    onClose(tab)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .black.opacity(0.5))
                        .padding(6)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.isHome ? "Новая вкладка" : tab.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if !tab.isHome {
                    Text(tab.currentURLString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(8)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tab.id == activeTabID ? Color.accentColor : .clear, lineWidth: 2)
        )
        .onTapGesture { onSelect(tab) }
    }
}
