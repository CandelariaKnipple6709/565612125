import SwiftUI

/// Sheet for the home screen's "+" tile: paste a URL, auto-fetch the
/// page's <title> to prefill a name, preview the site's favicon, then
/// save it as a regular Bookmark so it shows up on the home grid.
struct AddSiteSheet: View {
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var urlText: String = ""
    @State private var nameText: String = ""
    @State private var isFetchingTitle = false
    @State private var titleFetchTask: Task<Void, Never>?

    private var host: String? {
        var candidate = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.contains("://") { candidate = "https://" + candidate }
        return URL(string: candidate)?.host
    }

    private var faviconURL: URL? {
        guard let host, !host.isEmpty else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(host)")
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    fieldRow(label: "Ссылка") {
                        TextField("https://example.com", text: $urlText)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: urlText) { _ in scheduleTitleFetch() }
                    }
                    fieldRow(label: "Название") {
                        TextField("Название сайта", text: $nameText)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Новый сайт")
                } footer: {
                    if isFetchingTitle {
                        Text("Определяем название страницы…")
                    } else {
                        Text("Название подставится автоматически из заголовка страницы — его можно изменить вручную.")
                    }
                }

                if let faviconURL {
                    Section {
                        HStack(spacing: 12) {
                            AsyncImage(url: faviconURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFit()
                                default:
                                    Image(systemName: "globe")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 32, height: 32)
                            Text(host ?? "")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Добавить сайт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        save()
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func fieldRow<Field: View>(label: String, @ViewBuilder field: () -> Field) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            field()
        }
    }

    private func normalizedURLString() -> String {
        var s = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        return s
    }

    private func save() {
        let finalURL = normalizedURLString()
        let finalName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(finalName.isEmpty ? (host ?? finalURL) : finalName, finalURL)
        dismiss()
    }

    /// Debounced title fetch: waits briefly after the user stops typing/
    /// pasting, then does a cheap fetch-and-scan for <title> instead of
    /// fully parsing the HTML.
    private func scheduleTitleFetch() {
        titleFetchTask?.cancel()
        guard let url = URL(string: normalizedURLString()), url.host != nil else { return }
        titleFetchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            await fetchTitle(from: url)
        }
    }

    @MainActor
    private func fetchTitle(from url: URL) async {
        isFetchingTitle = true
        defer { isFetchingTitle = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if Task.isCancelled { return }
            let prefix = data.prefix(64 * 1024)
            guard let text = String(data: prefix, encoding: .utf8) else { return }
            if let title = AddSiteSheet.extractTitle(from: text), !title.isEmpty {
                // Only auto-fill if the user hasn't typed a custom name.
                if nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    nameText = title
                }
            }
        } catch {
            // Silently ignore — the user can still type a name manually.
        }
    }

    static func extractTitle(from html: String) -> String? {
        guard let openRange = html.range(of: "<title", options: .caseInsensitive) else { return nil }
        guard let gt = html.range(of: ">", range: openRange.upperBound..<html.endIndex) else { return nil }
        guard let closeRange = html.range(of: "</title>", options: .caseInsensitive, range: gt.upperBound..<html.endIndex) else { return nil }
        let raw = String(html[gt.upperBound..<closeRange.lowerBound])
        return raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }
}
